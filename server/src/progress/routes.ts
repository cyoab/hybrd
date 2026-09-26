import { createRoute, type OpenAPIHono } from "@hono/zod-openapi";
import type { AppDependencies, AppEnv } from "../api/dependencies";
import { errorResponse, protectedErrors, security } from "../api/schemas";
import {
  ActivityPageSchema,
  ActivityQuery,
  ComparisonPageSchema,
  ComparisonParams,
  ComparisonQuery,
  SummaryQuery,
  SummarySchema,
} from "./schemas";

export function registerProgressRoutes(
  app: OpenAPIHono<AppEnv>,
  deps: AppDependencies,
) {
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/progress/summary",
      operationId: "getProgressSummary",
      tags: ["Progress"],
      security,
      summary:
        "Current canonical progress on stored local training dates; no historical asOf queries.",
      request: { query: SummaryQuery },
      responses: {
        200: {
          description:
            "Consistent versioned progress snapshot. Private ETag revalidation is required.",
          content: { "application/json": { schema: SummarySchema } },
        },
        304: {
          description: "The authenticated athlete's summary has not changed.",
        },
        ...protectedErrors,
        403: errorResponse,
      },
    }),
    async (c) => {
      const result = await deps.progress.summary(
        c.get("authUserId"),
        c.req.valid("query"),
      );
      c.header("ETag", result.etag);
      c.header("Cache-Control", "private, no-cache, must-revalidate");
      c.header("Vary", "Authorization, Cookie, Origin");
      c.header("Expires", new Date(result.expiresAt).toUTCString());
      const matches = c.req
        .header("If-None-Match")
        ?.split(",")
        .map((s) => s.trim().replace(/^W\//, ""));
      if (matches?.some((s) => s === "*" || s === result.etag))
        return c.body(null, 304);
      return c.json(result.body, 200);
    },
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/progress/comparisons/{comparisonKey}",
      operationId: "getProgressComparison",
      tags: ["Progress"],
      security,
      summary:
        "Lifetime exact comparison history in ascending date/occurrence/result order. Edits expire cursors.",
      request: { params: ComparisonParams, query: ComparisonQuery },
      responses: {
        200: {
          description:
            "Bounded history page; cursor is bound to query and projection generation.",
          content: { "application/json": { schema: ComparisonPageSchema } },
        },
        ...protectedErrors,
        403: errorResponse,
        404: errorResponse,
        409: errorResponse,
      },
    }),
    async (c) =>
      c.json(
        await deps.progress.comparison(
          c.get("authUserId"),
          c.req.valid("param").comparisonKey,
          c.req.valid("query"),
        ),
        200,
      ),
  );
  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/progress/activity",
      operationId: "getProgressActivity",
      tags: ["Progress"],
      security,
      summary:
        "Eligible canonical activity in descending training-date/result-ID order, at most 366 days per query.",
      request: { query: ActivityQuery },
      responses: {
        200: {
          description:
            "Compact actuals without prescriptions, traces or full set histories.",
          content: { "application/json": { schema: ActivityPageSchema } },
        },
        ...protectedErrors,
        403: errorResponse,
        409: errorResponse,
      },
    }),
    async (c) =>
      c.json(
        await deps.progress.activity(c.get("authUserId"), c.req.valid("query")),
        200,
      ),
  );
}
