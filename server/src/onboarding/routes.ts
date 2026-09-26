import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import type { AppDependencies, AppEnv } from "../api/dependencies";
import { errorResponse, protectedErrors, security } from "../api/schemas";
import {
  CompleteInput,
  DraftSaved,
  OnboardingState,
  Receipt,
  SaveDraftInput,
} from "./schemas";
export function registerOnboardingRoutes(
  app: OpenAPIHono<AppEnv>,
  deps: AppDependencies,
) {
  const errors = {
    ...protectedErrors,
    403: errorResponse,
    409: errorResponse,
    422: errorResponse,
  };
  const headers = z.object({ "idempotency-key": z.string().uuid() });
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/onboarding",
      operationId: "getOnboarding",
      tags: ["Onboarding"],
      security,
      responses: {
        200: {
          description:
            "Restore account-owned setup; call immediately after bootstrap. No membership required.",
          content: { "application/json": { schema: OnboardingState } },
        },
        ...errors,
      },
    }),
    async (c) => c.json(await deps.onboarding.get(c.get("authUserId")), 200),
  );
  app.openapi(
    createRoute({
      method: "put",
      path: "/v1/onboarding/draft",
      operationId: "saveOnboardingDraft",
      tags: ["Onboarding"],
      security,
      request: {
        headers,
        body: {
          required: true,
          content: { "application/json": { schema: SaveDraftInput } },
        },
      },
      responses: {
        200: {
          description:
            "Full draft saved with optimistic concurrency. Replays return the original revision.",
          content: { "application/json": { schema: DraftSaved } },
        },
        ...errors,
      },
    }),
    async (c) =>
      c.json(
        await deps.onboarding.save(
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
      path: "/v1/onboarding/complete",
      operationId: "completeOnboarding",
      tags: ["Onboarding"],
      security,
      request: {
        headers,
        body: {
          required: true,
          content: { "application/json": { schema: CompleteInput } },
        },
      },
      responses: {
        200: {
          description:
            "Setup and receipt committed atomically. No entitlement granted or plan activated. latestSequence is a hint, never a replacement pull cursor.",
          content: { "application/json": { schema: Receipt } },
        },
        ...errors,
      },
    }),
    async (c) =>
      c.json(
        await deps.onboarding.complete(
          c.get("authUserId"),
          c.req.valid("header")["idempotency-key"],
          c.req.valid("json"),
        ),
        200,
      ),
  );
}
