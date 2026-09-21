import { expect, test } from "bun:test";
import { appleVerifier } from "../../src/billing/verifier";
import { readEnv } from "../../src/config/env";
import {
  developmentPolicy,
  PolicyConfigSchema,
  policyChecksum,
} from "../../src/config/policy";
import { DecisionRequestSchema } from "../../src/intelligence/jev/decision-registry";
import { openRouterProvider } from "../../src/intelligence/provider";
import { PlanInput } from "../../src/plans/schemas";
import { SyncPullQuerySchema } from "../../src/sync/schemas";
import { WorkoutInput } from "../../src/workouts/schemas";

const env = readEnv({
  DATABASE_URL: "postgres://test:test@localhost/hybrd_test",
  BETTER_AUTH_URL: "http://localhost:3000",
  BETTER_AUTH_SECRET: "test-only-long-enough-secret-for-unit-tests",
  OPENROUTER_API_KEY: "test-key",
  OPENROUTER_LLM_MODEL: "test/model",
});
const decision = DecisionRequestSchema.parse({
  decisionType: "strength_progression",
  schemaVersion: 1,
  context: {
    completionRate: 1,
    repsAchieved: 5,
    repsTarget: 5,
    lastRpe: 8,
    performanceTrend: null,
    consecutiveFailures: 0,
    runLoadTrend: null,
  },
});
const fake = (
  fn: (url: string, init?: RequestInit) => Response | Promise<Response>,
) =>
  ((url: unknown, init?: RequestInit) => fn(String(url), init)) as typeof fetch;
test("Jev uses the Decisions API and server-owned criteria rather than chat prompts", async () => {
  const provider = openRouterProvider(
    env,
    fake((url, init) => {
      expect(url).toBe("https://openrouter.ai/api/alpha/decisions");
      const body = JSON.parse(String(init?.body));
      expect(body.model).toBe(env.OPENROUTER_JEV_MODEL);
      expect(body.questions.decision.type).toBe("choice");
      expect(Object.keys(body.questions.decision.criteria)).toEqual([
        "reduce",
        "hold",
        "increase",
      ]);
      return Response.json({
        answers: {
          decision: {
            type: "choice",
            choice: "hold",
            confidence: 0.8,
            probabilities: { reduce: 0.1, hold: 0.8, increase: 0.1 },
          },
        },
        usage: { prompt_tokens: 30 },
        id: "request-1",
      });
    }),
  );
  const result = await provider.decision(decision);
  expect(result.result.decision).toBe("hold");
  expect(result.usage.inputTokens).toBe(30);
});
test("unsupported choices, malformed JSON and provider errors are sanitized", async () => {
  for (const response of [
    () =>
      Response.json({
        answers: {
          decision: {
            type: "choice",
            choice: "invented",
            confidence: 0.8,
            probabilities: { invented: 1 },
          },
        },
      }),
    () => new Response("not JSON"),
    () => new Response("secret provider token", { status: 429 }),
  ]) {
    try {
      await openRouterProvider(
        env,
        fake(() => response()),
      ).decision(decision);
      throw new Error("Unexpected success");
    } catch (error) {
      expect(String(error)).not.toContain("secret provider");
      expect(String(error)).not.toContain("Unexpected success");
    }
  }
});
test("coach uses bounded structured output, refuses truncated results and has no mutation tools", async () => {
  const response = {
    choices: [
      {
        message: {
          content: JSON.stringify({
            content: "Keep the plan.",
            actionProposals: [],
          }),
        },
        finish_reason: "stop",
      },
    ],
  };
  const provider = openRouterProvider(
    env,
    fake((_url, init) => {
      const body = JSON.parse(String(init?.body));
      expect(body.tools).toBeUndefined();
      expect(body.max_tokens).toBeLessThanOrEqual(1800);
      expect(body.response_format.type).toBe("json_schema");
      return Response.json(response);
    }),
  );
  expect(
    (await provider.chat({ context: {}, history: [], message: "Explain" }))
      .result.content,
  ).toBe("Keep the plan.");
  for (const choice of response.choices) choice.finish_reason = "length";
  await expect(
    provider.chat({ context: {}, history: [], message: "Explain" }),
  ).rejects.toThrow("contract");
});
test("Apple's real signed-data verifier rejects an unsigned or malformed JWS", async () => {
  const verifier = appleVerifier({
    ...env,
    STOREKIT_BUNDLE_ID: "test.hybrd",
    STOREKIT_ROOT_CERTIFICATES: new URL(
      "../../certificates/AppleRootCA-G3.cer",
      import.meta.url,
    ).pathname,
  });
  await expect(
    verifier.transaction("header.payload.signature"),
  ).rejects.toThrow("could not be verified");
  await expect(verifier.notification("not-signed")).rejects.toThrow(
    "could not be verified",
  );
});
test("policy checksums ignore key order and policies enforce internally consistent bounds", () => {
  expect(policyChecksum({ a: 1, b: 2 })).toBe(policyChecksum({ b: 2, a: 1 }));
  expect(
    PolicyConfigSchema.safeParse({
      ...developmentPolicy,
      interference: {
        lowerBeforeKeyRun: { warningHours: 10, severeHours: 20 },
      },
    }).success,
  ).toBe(false);
});
test("domain contracts reject raw traces, invalid units/dates and unsupported versions", () => {
  expect(
    DecisionRequestSchema.safeParse({ ...decision, schemaVersion: 2 }).success,
  ).toBe(false);
  expect(
    DecisionRequestSchema.safeParse({ ...decision, model: "client/model" })
      .success,
  ).toBe(false);
  expect(
    SyncPullQuerySchema.safeParse({
      deviceId: crypto.randomUUID(),
      cursor: "9223372036854775808",
    }).success,
  ).toBe(false);
  expect(
    WorkoutInput.safeParse({
      discipline: "running",
      trainingDate: "2026-02-30",
      timezone: "Fake/Timezone",
      completionStatus: "completed",
      sourceType: "healthkit",
      run: { distanceM: -1, durationS: 5, gps: [1, 2, 3] },
    }).success,
  ).toBe(false);
  expect(PlanInput.safeParse({ workouts: [] }).success).toBe(false);
});

test("rate limits expire and are isolated by account", async () => {
  const { rateLimiter } = await import("../../src/api/rate-limit");
  let now = 0;
  const limit = rateLimiter(2, 1000, () => now);
  limit("a");
  limit("a");
  expect(() => limit("a")).toThrow("Too many");
  expect(() => limit("b")).not.toThrow();
  now = 1001;
  expect(() => limit("a")).not.toThrow();
});
