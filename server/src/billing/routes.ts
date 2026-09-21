import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import type { AppEnv } from "../api/dependencies";
import { notImplemented } from "../api/errors";
import { errorResponse, protectedErrors, security } from "../api/schemas";

export function registerBillingRoutes(app: OpenAPIHono<AppEnv>) {
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/billing/apple/transactions",
      operationId: "submitAppleTransaction",
      tags: ["Billing"],
      security,
      summary:
        "Scaffold: signed transaction verification. No entitlement is granted.",
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
      responses: { 501: errorResponse, ...protectedErrors },
    }),
    () => notImplemented("StoreKit transaction verification"),
  );
}
