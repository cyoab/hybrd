import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import type { AppDependencies, AppEnv } from "../api/dependencies";
import { errorResponse, protectedErrors, security } from "../api/schemas";
import { DecisionRequestSchema } from "./jev/decision-registry";
import {
  ChatRequestSchema,
  ChatResponseSchema,
  DecisionResponseSchema,
} from "./schemas";

const headers = z.object({ "idempotency-key": z.string().uuid() });
const errors = {
  ...protectedErrors,
  403: errorResponse,
  409: errorResponse,
  429: errorResponse,
  502: errorResponse,
  503: errorResponse,
};
export function registerIntelligenceRoutes(
  app: OpenAPIHono<AppEnv>,
  deps: AppDependencies,
) {
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/intelligence/decision",
      operationId: "requestDecision",
      tags: ["Intelligence"],
      security,
      request: {
        headers,
        body: {
          required: true,
          content: { "application/json": { schema: DecisionRequestSchema } },
        },
      },
      responses: {
        200: {
          description: "Validated advisory choice; never changes a plan.",
          content: { "application/json": { schema: DecisionResponseSchema } },
        },
        ...errors,
      },
    }),
    async (c) =>
      c.json(
        await deps.intelligence.decision(
          c.get("authUserId"),
          c.req.valid("header")["idempotency-key"],
          c.req.valid("json"),
        ),
        200,
      ),
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/intelligence/chat",
      operationId: "sendCoachMessage",
      tags: ["Intelligence"],
      security,
      request: {
        headers,
        body: {
          required: true,
          content: { "application/json": { schema: ChatRequestSchema } },
        },
      },
      responses: {
        200: {
          description:
            "Persisted, validated response. Accept text/event-stream for a single complete event after validation; no unvalidated model tokens are emitted.",
          content: {
            "application/json": { schema: ChatResponseSchema },
            "text/event-stream": { schema: z.string() },
          },
        },
        ...errors,
      },
    }),
    async (c) => {
      const result = await deps.intelligence.chat(
        c.get("authUserId"),
        c.req.valid("header")["idempotency-key"],
        c.req.valid("json"),
      );
      if (c.req.header("Accept")?.includes("text/event-stream"))
        return c.body(
          `event: complete\ndata: ${JSON.stringify({ type: "complete", ...result })}\n\n`,
          200,
          {
            "Content-Type": "text/event-stream",
            "Cache-Control": "private, no-store",
          },
        );
      return c.json(result, 200);
    },
  );
}
