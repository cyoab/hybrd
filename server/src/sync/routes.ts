import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import type { AppEnv } from "../api/dependencies";
import { notImplemented } from "../api/errors";
import { errorResponse, protectedErrors, security } from "../api/schemas";
import { SyncPullQuerySchema, SyncPushSchema } from "./schemas";

export function registerSyncRoutes(app: OpenAPIHono<AppEnv>) {
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/sync/push",
      operationId: "pushSync",
      tags: ["Sync"],
      security,
      summary: "Scaffold: no mutations are accepted or acknowledged yet.",
      request: {
        body: {
          required: true,
          content: { "application/json": { schema: SyncPushSchema } },
        },
      },
      responses: { 501: errorResponse, ...protectedErrors },
    }),
    () => notImplemented("Sync push"),
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/sync/pull",
      operationId: "pullSync",
      tags: ["Sync"],
      security,
      summary: "Scaffold: no change feed is served yet.",
      request: { query: SyncPullQuerySchema },
      responses: { 501: errorResponse, ...protectedErrors },
    }),
    () => notImplemented("Sync pull"),
  );
}
