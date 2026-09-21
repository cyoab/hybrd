import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import type { AppDependencies, AppEnv } from "../api/dependencies";
import {
  EntitlementSchema,
  errorResponse,
  protectedErrors,
  security,
} from "../api/schemas";
export function registerBillingRoutes(
  app: OpenAPIHono<AppEnv>,
  deps: AppDependencies,
) {
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/billing/apple/transactions",
      operationId: "submitAppleTransaction",
      tags: ["Billing"],
      security,
      request: {
        body: {
          required: true,
          content: {
            "application/json": {
              schema: z
                .object({ signedTransaction: z.string().min(1).max(32000) })
                .strict()
                .openapi("AppleTransactionSubmission"),
            },
          },
        },
      },
      responses: {
        200: {
          description:
            "Verified effective entitlements. Send the athlete UUID as StoreKit appAccountToken.",
          content: {
            "application/json": {
              schema: z.object({ entitlements: z.array(EntitlementSchema) }),
            },
          },
        },
        ...protectedErrors,
        403: errorResponse,
        409: errorResponse,
        503: errorResponse,
      },
    }),
    async (c) =>
      c.json(
        await deps.billing.submit(
          c.get("authUserId"),
          c.req.valid("json").signedTransaction,
        ),
        200,
      ),
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/webhooks/apple",
      operationId: "appleServerNotification",
      tags: ["Billing"],
      summary:
        "App Store Server Notifications V2. Authentication is the verified Apple JWS, not a user session.",
      request: {
        body: {
          required: true,
          content: {
            "application/json": {
              schema: z
                .object({ signedPayload: z.string().min(1).max(64000) })
                .strict(),
            },
          },
        },
      },
      responses: {
        204: {
          description: "Verified notification processed or deduplicated.",
        },
        400: errorResponse,
        413: errorResponse,
        500: errorResponse,
        503: errorResponse,
      },
    }),
    async (c) => {
      await deps.billing.notification(c.req.valid("json").signedPayload);
      return c.body(null, 204);
    },
  );
}
