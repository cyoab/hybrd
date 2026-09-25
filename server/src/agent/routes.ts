import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import { streamSSE } from "hono/streaming";
import type { AppDependencies, AppEnv } from "../api/dependencies";
import { ApiError } from "../api/errors";
import {
  CursorSchema,
  errorResponse,
  protectedErrors,
  security,
} from "../api/schemas";
import {
  AgentCapabilities,
  AgentMemory,
  AgentRun,
  AgentRunInput,
  MemoryInput,
  terminal,
} from "./schemas";

const errors = {
  ...protectedErrors,
  403: errorResponse,
  404: errorResponse,
  409: errorResponse,
  503: errorResponse,
};
const params = z.object({ id: z.string().uuid() });
const tags = ["Agent"];
export function registerAgentRoutes(
  app: OpenAPIHono<AppEnv>,
  deps: AppDependencies,
) {
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/agent/capabilities",
      operationId: "getAgentCapabilities",
      tags,
      security,
      responses: {
        200: {
          description:
            "Environment availability, separate from athlete consent and entitlement. Plan mutations are not enabled in this version.",
          content: { "application/json": { schema: AgentCapabilities } },
        },
        ...errors,
      },
    }),
    async (c) =>
      c.json(await deps.agent.capabilities(c.get("authUserId")), 200),
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/agent/runs",
      operationId: "createAgentRun",
      tags,
      security,
      request: {
        headers: z.object({ "idempotency-key": z.string().uuid() }),
        body: {
          required: true,
          content: { "application/json": { schema: AgentRunInput } },
        },
      },
      responses: {
        202: {
          description:
            "Durable run accepted, or the existing run for an exact retry. No provider call occurs on the request path.",
          content: { "application/json": { schema: AgentRun } },
        },
        ...errors,
      },
    }),
    async (c) =>
      c.json(
        await deps.agent.create(
          c.get("authUserId"),
          c.req.valid("header")["idempotency-key"],
          c.req.valid("json"),
        ),
        202,
      ),
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/agent/runs/{id}",
      operationId: "getAgentRun",
      tags,
      security,
      request: { params },
      responses: {
        200: {
          description:
            "Canonical run status and validated final artifact. artifactStale indicates a corrected/deleted analyzed result.",
          content: { "application/json": { schema: AgentRun } },
        },
        ...errors,
      },
    }),
    async (c) =>
      c.json(
        await deps.agent.get(c.get("authUserId"), c.req.valid("param").id),
        200,
      ),
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/agent/runs/{id}/cancel",
      operationId: "cancelAgentRun",
      tags,
      security,
      request: { params },
      responses: {
        200: {
          description:
            "Idempotent cancellation. A provider call already in flight may still incur usage; its answer cannot publish after cancellation.",
          content: { "application/json": { schema: AgentRun } },
        },
        ...errors,
      },
    }),
    async (c) =>
      c.json(
        await deps.agent.cancel(c.get("authUserId"), c.req.valid("param").id),
        200,
      ),
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/agent/runs/{id}/events",
      operationId: "streamAgentRunEvents",
      tags,
      security,
      request: {
        params,
        headers: z.object({ "last-event-id": CursorSchema.optional() }),
      },
      responses: {
        200: {
          description:
            "Replayable SSE with decimal sequence IDs. Status/tool/artifact/completion events are durable; heartbeat/error events have no ID. Connection rotates after 25 seconds; reconnect with Last-Event-ID. Replay expires after seven days; restore with GET status. Events contain no unvalidated model prose.",
          content: { "text/event-stream": { schema: z.string() } },
        },
        ...errors,
      },
    }),
    async (c) => {
      const userId = c.get("authUserId"),
        id = c.req.valid("param").id;
      let cursor = c.req.valid("header")["last-event-id"] ?? "0";
      let batch = await deps.agent.events(userId, id, cursor);
      c.header("X-Accel-Buffering", "no");
      return streamSSE(c, async (stream) => {
        const started = Date.now();
        try {
          while (!stream.aborted && Date.now() - started < 25000) {
            for (const item of batch.events) {
              await stream.writeSSE({
                id: item.id,
                event: item.type,
                data: JSON.stringify(item),
                retry: 1000,
              });
              cursor = item.id;
            }
            if (
              terminal(batch.run.status) &&
              BigInt(cursor) >= BigInt(batch.run.lastEventId)
            )
              return;
            await stream.writeSSE({ event: "heartbeat", data: "{}" });
            await stream.sleep(1000);
            if (stream.aborted) return;
            if ((await deps.authenticate(c.req.raw.headers)) !== userId)
              throw new ApiError(401, "UNAUTHORIZED", "The session expired.");
            batch = await deps.agent.events(userId, id, cursor);
          }
        } catch (error) {
          if (!stream.aborted)
            await stream.writeSSE({
              event: "error",
              data: JSON.stringify({
                errorCode:
                  error instanceof ApiError
                    ? error.code
                    : "AGENT_STREAM_UNAVAILABLE",
              }),
            });
        }
      });
    },
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/agent/memories",
      operationId: "listAgentMemories",
      tags,
      security,
      responses: {
        200: {
          description:
            "User-managed memory, limited to 20 entries. Automatic learning is not enabled yet.",
          content: {
            "application/json": {
              schema: z.object({ memories: z.array(AgentMemory) }),
            },
          },
        },
        ...errors,
      },
    }),
    async (c) => c.json(await deps.agent.memories(c.get("authUserId")), 200),
  );
  app.openapi(
    createRoute({
      method: "put",
      path: "/v1/agent/memories/{id}",
      operationId: "putAgentMemory",
      tags,
      security,
      request: {
        params,
        body: {
          required: true,
          content: { "application/json": { schema: MemoryInput } },
        },
      },
      responses: {
        200: {
          description:
            "Create with null expectedRevision or replace with the current revision. Resets cached conversation context and cancels pending runs.",
          content: { "application/json": { schema: AgentMemory } },
        },
        ...errors,
      },
    }),
    async (c) =>
      c.json(
        await deps.agent.putMemory(
          c.get("authUserId"),
          c.req.valid("param").id,
          c.req.valid("json"),
        ),
        200,
      ),
  );
  app.openapi(
    createRoute({
      method: "delete",
      path: "/v1/agent/memories/{id}",
      operationId: "forgetAgentMemory",
      tags,
      security,
      request: { params, headers: z.object({ "if-match": CursorSchema }) },
      responses: {
        204: {
          description:
            "Memory removed; pending runs cancelled and old conversation context excluded from future prompts. Workout history remains intact.",
        },
        ...errors,
      },
    }),
    async (c) => {
      await deps.agent.forgetMemory(
        c.get("authUserId"),
        c.req.valid("param").id,
        c.req.valid("header")["if-match"],
      );
      return c.body(null, 204);
    },
  );
}
