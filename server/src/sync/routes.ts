import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import type { AppDependencies, AppEnv } from "../api/dependencies";
import { errorResponse, protectedErrors, security } from "../api/schemas";
import {
  SyncAckInput,
  SyncPullQuerySchema,
  SyncPullResponse,
  SyncPushResponse,
  SyncPushSchema,
} from "./schemas";
export function registerSyncRoutes(
  app: OpenAPIHono<AppEnv>,
  deps: AppDependencies,
) {
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/sync/push",
      operationId: "pushSync",
      tags: ["Sync"],
      security,
      summary: "Apply each mutation atomically; replay identical mutation IDs.",
      request: {
        body: {
          required: true,
          content: { "application/json": { schema: SyncPushSchema } },
        },
      },
      responses: {
        200: {
          description:
            "Per-mutation outcomes. Conflicts do not roll back other mutations.",
          content: { "application/json": { schema: SyncPushResponse } },
        },
        ...protectedErrors,
        403: errorResponse,
      },
    }),
    async (c) =>
      c.json(
        await deps.sync.push(c.get("authUserId"), c.req.valid("json")),
        200,
      ),
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/sync/pull",
      operationId: "pullSync",
      tags: ["Sync"],
      security,
      summary:
        "Read ordered events containing the current canonical aggregate or a tombstone.",
      request: { query: SyncPullQuerySchema },
      responses: {
        200: {
          description:
            "Persist entities and nextCursor together before acknowledging.",
          content: { "application/json": { schema: SyncPullResponse } },
        },
        ...protectedErrors,
        403: errorResponse,
      },
    }),
    async (c) =>
      c.json(
        await deps.sync.pull(c.get("authUserId"), c.req.valid("query")),
        200,
      ),
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/sync/ack",
      operationId: "acknowledgeSync",
      tags: ["Sync"],
      security,
      request: {
        body: {
          required: true,
          content: { "application/json": { schema: SyncAckInput } },
        },
      },
      responses: {
        204: { description: "Monotonic durable-device cursor recorded." },
        ...protectedErrors,
        403: errorResponse,
      },
    }),
    async (c) => {
      const input = c.req.valid("json");
      await deps.sync.acknowledge(
        c.get("authUserId"),
        input.deviceId,
        input.cursor,
      );
      return c.body(null, 204);
    },
  );
}
