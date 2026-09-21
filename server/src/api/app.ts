import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";
import { bodyLimit } from "hono/body-limit";
import { cors } from "hono/cors";
import { HTTPException } from "hono/http-exception";
import { secureHeaders } from "hono/secure-headers";
import { registerBillingRoutes } from "../billing/routes";
import { registerIntelligenceRoutes } from "../intelligence/routes";
import { registerSyncRoutes } from "../sync/routes";
import { log } from "../telemetry/logger";
import type { AppDependencies, AppEnv } from "./dependencies";
import { ApiError, notImplemented } from "./errors";
import {
  BootstrapSchema,
  DeviceInputSchema,
  DeviceSchema,
  EntitlementSchema,
  errorResponse,
  protectedErrors,
  security,
  TrainingPolicySchema,
} from "./schemas";

export const openApiInfo = {
  openapi: "3.1.0" as const,
  info: {
    title: "hybrd API",
    version: "0.1.0",
    description:
      "Local-first training control plane. Operations marked scaffold return 501 and do not persist or acknowledge work. Better Auth endpoints live under /api/auth and use the provider's contract.",
  },
  servers: [
    {
      url: "http://localhost:3000",
      description:
        "Local development; override in the generated client for other environments.",
    },
  ],
};

export function createApp(
  deps: AppDependencies,
  options: { trustedOrigins?: string[]; logging?: boolean } = {},
) {
  const app = new OpenAPIHono<AppEnv>({
    defaultHook: (result, c) => {
      if (!result.success)
        return c.json(
          {
            error: {
              code: "VALIDATION_ERROR",
              message: "The request does not match the API contract.",
              details: {
                fields: result.error.issues.map((issue) =>
                  issue.path.join("."),
                ),
              },
              requestId: c.get("requestId"),
            },
          },
          400,
        );
    },
  });

  app.use("*", async (c, next) => {
    c.set("requestId", crypto.randomUUID());
    c.header("X-Request-Id", c.get("requestId"));
    const start = performance.now();
    await next();
    if (options.logging !== false && !c.req.path.startsWith("/health/"))
      log({
        event: "http_request",
        requestId: c.get("requestId"),
        method: c.req.method,
        route: c.req.routePath || "unmatched",
        status: c.res.status,
        durationMs: Math.round(performance.now() - start),
      });
  });
  app.use("*", secureHeaders());
  app.use(
    "*",
    cors({
      origin: options.trustedOrigins ?? [],
      credentials: true,
      exposeHeaders: ["X-Request-Id", "ETag", "set-auth-token"],
    }),
  );
  app.use(
    "*",
    bodyLimit({
      maxSize: 1024 * 1024,
      onError: () => {
        throw new ApiError(
          413,
          "PAYLOAD_TOO_LARGE",
          "Request bodies must not exceed 1 MiB.",
        );
      },
    }),
  );
  app.onError((error, c) => {
    const status =
      error instanceof ApiError || error instanceof HTTPException
        ? error.status
        : 500;
    const code =
      error instanceof ApiError
        ? error.code
        : status === 400
          ? "BAD_REQUEST"
          : "INTERNAL_ERROR";
    if (status >= 500 && status !== 501 && options.logging !== false)
      log({
        event: "request_error",
        requestId: c.get("requestId"),
        errorType: error.name,
        status,
      });
    return c.json(
      {
        error: {
          code,
          message:
            error instanceof ApiError
              ? error.message
              : status === 400
                ? "Malformed request."
                : "The request could not be completed.",
          requestId: c.get("requestId"),
        },
      },
      status,
    );
  });
  app.notFound((c) =>
    c.json(
      {
        error: {
          code: "NOT_FOUND",
          message: "Route not found.",
          requestId: c.get("requestId"),
        },
      },
      404,
    ),
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/health/live",
      operationId: "getLiveness",
      tags: ["Health"],
      responses: {
        200: {
          description: "Process is running.",
          content: {
            "application/json": {
              schema: z.object({ status: z.literal("ok") }),
            },
          },
        },
      },
    }),
    (c) => c.json({ status: "ok" as const }, 200),
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/health/ready",
      operationId: "getReadiness",
      tags: ["Health"],
      responses: {
        200: {
          description: "Database is reachable.",
          content: {
            "application/json": {
              schema: z.object({ status: z.literal("ready") }),
            },
          },
        },
        503: errorResponse,
      },
    }),
    async (c) => {
      try {
        await deps.checkDatabase();
      } catch {
        throw new ApiError(
          503,
          "DATABASE_UNAVAILABLE",
          "The database is not ready.",
        );
      }
      return c.json({ status: "ready" as const }, 200);
    },
  );

  app.all("/api/auth/*", (c) => deps.handleAuth(c.req.raw));
  app.use("/v1/*", async (c, next) => {
    c.header("Cache-Control", "private, no-store");
    const authUserId = await deps.authenticate(c.req.raw.headers);
    if (!authUserId)
      throw new ApiError(401, "UNAUTHORIZED", "A valid session is required.");
    c.set("authUserId", authUserId);
    await next();
  });

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/bootstrap",
      operationId: "getBootstrap",
      tags: ["Athlete"],
      security,
      request: { query: z.object({ deviceId: z.string().uuid().optional() }) },
      responses: {
        200: {
          description:
            "Account state and capabilities. Sync is unavailable in this scaffold.",
          content: { "application/json": { schema: BootstrapSchema } },
        },
        ...protectedErrors,
        403: errorResponse,
      },
    }),
    async (c) =>
      c.json(
        await deps.bootstrap(
          c.get("authUserId"),
          c.req.valid("query").deviceId,
        ),
        200,
      ),
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/config/training-policy",
      operationId: "getTrainingPolicy",
      tags: ["Configuration"],
      security,
      request: {
        headers: z.object({ "if-none-match": z.string().optional() }),
      },
      responses: {
        200: {
          description:
            "Latest published policy. Cache only if schemaVersion is supported.",
          headers: { ETag: { schema: { type: "string" } } },
          content: { "application/json": { schema: TrainingPolicySchema } },
        },
        304: { description: "Cached policy is current." },
        503: errorResponse,
        ...protectedErrors,
      },
    }),
    async (c) => {
      const policy = await deps.trainingPolicy();
      if (!policy)
        throw new ApiError(
          503,
          "POLICY_UNAVAILABLE",
          "No training policy has been published.",
        );
      const etag = `"${policy.checksum}"`;
      c.header("ETag", etag);
      c.header("Cache-Control", "private, no-cache");
      const matches = c.req
        .header("If-None-Match")
        ?.split(",")
        .some(
          (value) =>
            value.trim() === "*" || value.trim().replace(/^W\//, "") === etag,
        );
      if (matches) return c.body(null, 304);
      return c.json(policy, 200);
    },
  );

  const deviceParams = z.object({ deviceId: z.string().uuid() });
  app.openapi(
    createRoute({
      method: "put",
      path: "/v1/devices/{deviceId}",
      operationId: "registerDevice",
      tags: ["Devices"],
      security,
      request: {
        params: deviceParams,
        body: {
          required: true,
          content: { "application/json": { schema: DeviceInputSchema } },
        },
      },
      responses: {
        200: {
          description:
            "Idempotent registration of the authenticated athlete's installation.",
          content: { "application/json": { schema: DeviceSchema } },
        },
        403: errorResponse,
        409: errorResponse,
        ...protectedErrors,
      },
    }),
    async (c) => {
      const { deviceId } = c.req.valid("param");
      await deps.registerDevice(
        c.get("authUserId"),
        deviceId,
        c.req.valid("json"),
      );
      return c.json({ id: deviceId, registered: true as const }, 200);
    },
  );
  app.openapi(
    createRoute({
      method: "delete",
      path: "/v1/devices/{deviceId}",
      operationId: "revokeDevice",
      tags: ["Devices"],
      security,
      request: { params: deviceParams },
      responses: {
        204: {
          description:
            "Installation revoked. Repeated requests have the same effect.",
        },
        403: errorResponse,
        ...protectedErrors,
      },
    }),
    async (c) => {
      await deps.revokeDevice(
        c.get("authUserId"),
        c.req.valid("param").deviceId,
      );
      return c.body(null, 204);
    },
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/billing/entitlements",
      operationId: "getEntitlements",
      tags: ["Billing"],
      security,
      responses: {
        200: {
          description:
            "Canonical entitlement records; an empty array grants no access.",
          content: {
            "application/json": {
              schema: z.object({ entitlements: z.array(EntitlementSchema) }),
            },
          },
        },
        403: errorResponse,
        ...protectedErrors,
      },
    }),
    async (c) =>
      c.json(
        { entitlements: await deps.entitlements(c.get("authUserId")) },
        200,
      ),
  );

  registerSyncRoutes(app);
  registerIntelligenceRoutes(app);
  registerBillingRoutes(app);
  app.openapi(
    createRoute({
      method: "delete",
      path: "/v1/account",
      operationId: "deleteAccount",
      tags: ["Account"],
      security,
      summary: "Scaffold: account deletion is pending a retention policy.",
      responses: { 501: errorResponse, ...protectedErrors },
    }),
    () => notImplemented("Account deletion"),
  );

  app.openAPIRegistry.registerComponent("securitySchemes", "bearerAuth", {
    type: "http",
    scheme: "bearer",
    description: "Better Auth session token. Store it in the iOS Keychain.",
  });
  app.doc31("/openapi.json", openApiInfo);
  app.get("/", (c) =>
    c.json({
      name: "hybrd-api",
      version: "0.1.0",
      openapi: "/openapi.json",
      readiness: "/health/ready",
    }),
  );
  return app;
}
