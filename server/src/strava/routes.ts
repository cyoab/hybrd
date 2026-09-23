import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import type { AppDependencies, AppEnv } from "../api/dependencies";
import { errorResponse, protectedErrors, security } from "../api/schemas";
import {
  CompleteInput,
  ConnectInput,
  StatusSchema,
  WebhookInput,
} from "./schemas";

const json = <T extends z.ZodType>(schema: T) => ({
  "application/json": { schema },
});
const errors = {
  ...protectedErrors,
  409: errorResponse,
  502: errorResponse,
  503: errorResponse,
};
export function registerStravaRoutes(
  app: OpenAPIHono<AppEnv>,
  deps: AppDependencies,
) {
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/integrations/strava",
      operationId: "getStravaConnection",
      tags: ["Strava"],
      security,
      responses: {
        200: {
          description:
            "Connection, reviewed-history suggestions and recent background jobs; never includes tokens.",
          content: json(StatusSchema),
        },
        ...errors,
      },
    }),
    async (c) => c.json(await deps.strava.status(c.get("authUserId")), 200),
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/integrations/strava/connect",
      operationId: "connectStrava",
      tags: ["Strava"],
      security,
      request: { body: { required: true, content: json(ConnectInput) } },
      responses: {
        200: {
          description:
            "Open authorizationUrl in a system authentication session. Auto-publish applies to future workout saves.",
          content: json(
            z.object({
              authorizationUrl: z.url(),
              state: z.string(),
              expiresInSeconds: z.number(),
            }),
          ),
        },
        ...errors,
      },
    }),
    async (c) =>
      c.json(
        await deps.strava.connect(
          c.get("authUserId"),
          c.req.valid("json").autoPublish,
        ),
        200,
      ),
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/integrations/strava/complete",
      operationId: "completeStravaConnection",
      tags: ["Strava"],
      security,
      request: { body: { required: true, content: json(CompleteInput) } },
      responses: {
        200: {
          description:
            "Optional native code handoff; the standard server callback completes this automatically.",
          content: json(z.object({ connected: z.literal(true) })),
        },
        ...errors,
      },
    }),
    async (c) => {
      const body = c.req.valid("json");
      return c.json(
        await deps.strava.complete(
          body.state,
          body.code,
          body.scope,
          c.get("authUserId"),
        ),
        200,
      );
    },
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/integrations/strava/history",
      operationId: "refreshStravaHistory",
      tags: ["Strava"],
      security,
      responses: {
        202: {
          description:
            "Coalesced background refresh of the previous 365 days; poll connection status for suggestions.",
          content: json(z.object({ jobId: z.uuid() })),
        },
        ...errors,
      },
    }),
    async (c) =>
      c.json(await deps.strava.refreshHistory(c.get("authUserId")), 202),
  );
  app.openapi(
    createRoute({
      method: "patch",
      path: "/v1/integrations/strava",
      operationId: "updateStravaSettings",
      tags: ["Strava"],
      security,
      request: { body: { required: true, content: json(ConnectInput) } },
      responses: {
        204: {
          description:
            "Auto-publish preference updated. Turning it on never publishes old history.",
        },
        ...errors,
      },
    }),
    async (c) => {
      await deps.strava.settings(
        c.get("authUserId"),
        c.req.valid("json").autoPublish,
      );
      return c.body(null, 204);
    },
  );
  app.openapi(
    createRoute({
      method: "delete",
      path: "/v1/integrations/strava",
      operationId: "disconnectStrava",
      tags: ["Strava"],
      security,
      responses: {
        202: {
          description:
            "Stopped new sync, purged imported preview, and queued token revocation.",
        },
        ...errors,
      },
    }),
    async (c) => {
      await deps.strava.disconnect(c.get("authUserId"));
      return c.body(null, 202);
    },
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/integrations/strava/jobs/{jobId}/retry",
      operationId: "retryStravaJob",
      tags: ["Strava"],
      security,
      request: { params: z.object({ jobId: z.uuid() }) },
      responses: {
        202: {
          description:
            "Queued a safe retry. Ambiguous activity creation is never automatically retried.",
        },
        ...errors,
      },
    }),
    async (c) => {
      await deps.strava.retry(c.get("authUserId"), c.req.valid("param").jobId);
      return c.body(null, 202);
    },
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/integrations/strava/jobs/{jobId}/reconcile",
      operationId: "reconcileStravaPublish",
      tags: ["Strava"],
      security,
      request: {
        params: z.object({ jobId: z.uuid() }),
        body: {
          required: true,
          content: json(
            z
              .object({ remoteActivityId: z.string().regex(/^\d+$/).max(30) })
              .strict(),
          ),
        },
      },
      responses: {
        202: {
          description:
            "Verify a suspected Strava activity against this workout's reference. Never creates an activity.",
        },
        ...errors,
      },
    }),
    async (c) => {
      await deps.strava.reconcile(
        c.get("authUserId"),
        c.req.valid("param").jobId,
        c.req.valid("json").remoteActivityId,
      );
      return c.body(null, 202);
    },
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/integrations/strava/callback",
      operationId: "stravaOAuthCallback",
      tags: ["Strava"],
      request: {
        query: z.object({
          state: z.string().max(128).optional(),
          code: z.string().max(2000).optional(),
          scope: z.string().max(1000).optional(),
          error: z.string().max(100).optional(),
        }),
      },
      responses: {
        302: {
          description:
            "Return to the configured app link with status only. One-time OAuth state binds the callback to a signed-in athlete.",
        },
        400: errorResponse,
      },
    }),
    async (c) => {
      c.header("Cache-Control", "no-store");
      c.header("Referrer-Policy", "no-referrer");
      return c.redirect(await deps.strava.callback(c.req.valid("query")), 302);
    },
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/webhooks/strava/{secret}",
      operationId: "verifyStravaWebhook",
      tags: ["Strava"],
      request: {
        params: z.object({ secret: z.string().max(200) }),
        query: z.object({
          "hub.mode": z.literal("subscribe"),
          "hub.verify_token": z.string().max(200),
          "hub.challenge": z.string().max(500),
        }),
      },
      responses: {
        200: {
          description: "Strava subscription verification.",
          content: json(z.object({ "hub.challenge": z.string() })),
        },
        400: errorResponse,
        404: errorResponse,
      },
    }),
    (c) => {
      const q = c.req.valid("query");
      deps.strava.verifyWebhook(
        c.req.valid("param").secret,
        q["hub.verify_token"],
      );
      return c.json({ "hub.challenge": q["hub.challenge"] }, 200);
    },
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/webhooks/strava/{secret}",
      operationId: "receiveStravaEvent",
      tags: ["Strava"],
      request: {
        params: z.object({ secret: z.string().max(200) }),
        body: { required: true, content: json(WebhookInput) },
      },
      responses: {
        200: {
          description:
            "Event durably handled; no Strava network calls in this request.",
          content: json(z.object({ received: z.literal(true) })),
        },
        400: errorResponse,
        404: errorResponse,
      },
    }),
    async (c) => {
      await deps.strava.webhook(
        c.req.valid("param").secret,
        c.req.valid("json"),
      );
      return c.json({ received: true as const }, 200);
    },
  );
}
