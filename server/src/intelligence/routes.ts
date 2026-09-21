import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import type { AppEnv } from "../api/dependencies";
import { notImplemented } from "../api/errors";
import { errorResponse, protectedErrors, security } from "../api/schemas";
import { DecisionRequestSchema } from "./jev/decision-registry";

const ChatRequestSchema = z
  .object({
    threadId: z.string().uuid(),
    message: z.string().min(1).max(8000),
    context: z
      .object({
        schemaVersion: z.literal(1),
        activePlanVersionId: z.string().uuid().nullable(),
        summary: z.string().max(12000),
      })
      .strict(),
  })
  .strict()
  .openapi("CoachRequest");

export function registerIntelligenceRoutes(app: OpenAPIHono<AppEnv>) {
  const idempotencyHeaders = z.object({ "idempotency-key": z.string().uuid() });
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/intelligence/decision",
      operationId: "requestDecision",
      tags: ["Intelligence"],
      security,
      summary: "Scaffold: structured decision gateway. No provider is called.",
      request: {
        headers: idempotencyHeaders,
        body: {
          required: true,
          content: { "application/json": { schema: DecisionRequestSchema } },
        },
      },
      responses: { 501: errorResponse, ...protectedErrors },
    }),
    () => notImplemented("Structured decisions"),
  );
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/intelligence/chat",
      operationId: "sendCoachMessage",
      tags: ["Intelligence"],
      security,
      summary:
        "Scaffold: coach gateway. Streaming and proposal contracts are not implemented.",
      request: {
        headers: idempotencyHeaders,
        body: {
          required: true,
          content: { "application/json": { schema: ChatRequestSchema } },
        },
      },
      responses: { 501: errorResponse, ...protectedErrors },
    }),
    () => notImplemented("AI coaching"),
  );
}
