import { describe, expect, test } from "bun:test";
import {
  agentUsage,
  openRouterAgent,
  respondTool,
} from "../../src/agent/provider";
import { AgentRun, AgentRunInput } from "../../src/agent/schemas";
import { workoutMetrics } from "../../src/agent/tools";
import { readEnv } from "../../src/config/env";

const env = readEnv({
  NODE_ENV: "test",
  DATABASE_URL: "postgres://test:test@localhost/hybrd_test",
  BETTER_AUTH_URL: "http://localhost:3000",
  BETTER_AUTH_SECRET: "test-secret-longer-than-thirty-two-characters",
  OPENROUTER_API_KEY: "synthetic-key",
  AGENT_MODEL: "test/model",
  AGENT_CACHE_MODE: "ephemeral",
});
describe("agent boundaries", () => {
  test("shared iOS examples remain valid request and artifact contracts", async () => {
    for (const file of ["agent-run.json", "agent-analysis.json"])
      expect(
        AgentRunInput.safeParse(
          await Bun.file(
            new URL(`../../../contracts/examples/${file}`, import.meta.url),
          ).json(),
        ).success,
      ).toBe(true);
    expect(
      AgentRun.safeParse(
        await Bun.file(
          new URL(
            "../../../contracts/examples/agent-run-succeeded.json",
            import.meta.url,
          ),
        ).json(),
      ).success,
    ).toBe(true);
  });
  test("analysis input must identify a precise owned revision; callers cannot grant tools", () => {
    const input = {
      schemaVersion: 1,
      deviceId: crypto.randomUUID(),
      task: "analyze_workout",
      message: "Analyze this run",
    };
    expect(AgentRunInput.safeParse(input).success).toBe(false);
    const valid = {
      ...input,
      workoutResultId: crypto.randomUUID(),
      expectedWorkoutRevision: "3",
    };
    expect(AgentRunInput.safeParse(valid).success).toBe(true);
    expect(
      AgentRunInput.safeParse({ ...valid, allowedTools: ["delete_account"] })
        .success,
    ).toBe(false);
  });
  test("metrics distinguish elapsed/moving pace, zero distance, missing HR and overlapping segments", () => {
    const result = {
      id: "r",
      revision: "2",
      discipline: "running",
      durationS: 1800,
      run: {
        distanceM: 5000,
        durationS: 1800,
        movingDurationS: null,
        avgHrBpm: null,
        maxHrBpm: null,
        segments: [
          { id: "km", durationS: 300, distanceM: 1000 },
          { id: "interval", durationS: 300, distanceM: 1000 },
        ],
      },
    };
    const measured = workoutMetrics(result);
    expect(
      measured.metrics.find((m) => m.ref.endsWith("meanPace")),
    ).toMatchObject({
      value: 360,
      label: "Mean elapsed pace (includes pauses)",
    });
    expect(measured.metrics.some((m) => m.ref.includes("HrBpm"))).toBe(false);
    expect(
      measured.metrics.find((m) => m.ref.endsWith("run.distanceM"))?.value,
    ).toBe(5000);
    expect(
      workoutMetrics({
        ...result,
        run: { ...result.run, movingDurationS: 1500 },
      }).metrics.find((m) => m.ref.endsWith("meanPace"))?.value,
    ).toBe(300);
    expect(
      workoutMetrics({
        ...result,
        run: { ...result.run, distanceM: 0 },
      }).metrics.some((m) => m.ref.endsWith("meanPace")),
    ).toBe(false);
  });
  test("failed/skipped sets cannot inflate completed-set counts or load totals", () => {
    const result = workoutMetrics({
      id: "r",
      revision: "1",
      discipline: "strength",
      exercises: [
        {
          id: "e",
          sets: [
            {
              id: "s1",
              status: "completed",
              reps: 5,
              loadKg: 0,
              loadConvention: "bodyweight",
              rir: null,
            },
            { id: "s2", status: "skipped", reps: 5, loadKg: 60 },
          ],
        },
      ],
    });
    expect(
      result.metrics.find((m) => m.ref.endsWith("completedSets"))?.value,
    ).toBe(1);
    expect(result.metrics.some((m) => m.ref.includes("s2"))).toBe(false);
    expect(result.metrics.find((m) => m.ref.endsWith("loadKg"))).toMatchObject({
      value: 0,
      label: "Recorded bodyweight load",
    });
  });
  test("cache reads, writes and reasoning usage are accounted without inventing missing values", () => {
    expect(
      agentUsage({
        usage: {
          prompt_tokens: 2000,
          completion_tokens: 30,
          cost: 0.002,
          prompt_tokens_details: {
            cached_tokens: 1500,
            cache_write_tokens: 500,
          },
          completion_tokens_details: { reasoning_tokens: 10 },
        },
      }),
    ).toMatchObject({
      inputTokens: 2000,
      cachedInputTokens: 1500,
      cacheWriteTokens: 500,
      reasoningTokens: 10,
      costUsdMicros: 2000,
    });
    expect(agentUsage({})).not.toHaveProperty("costUsdMicros");
  });
  test("provider pins a cache-aware session, excludes fallback and rejects prose/truncated responses", async () => {
    const requests: Record<string, unknown>[] = [];
    let finish = "tool_calls";
    const provider = openRouterAgent(
      env,
      async (_url: unknown, init: RequestInit) => {
        requests.push(JSON.parse(String(init.body)));
        return Response.json({
          choices: [
            {
              finish_reason: finish,
              message: {
                tool_calls: [
                  {
                    id: "call1",
                    type: "function",
                    function: { name: "respond", arguments: "{}" },
                  },
                ],
              },
            },
          ],
          usage: {
            prompt_tokens: 1300,
            prompt_tokens_details: { cached_tokens: 1000 },
          },
        });
      },
    );
    const input = {
      sessionId: "opaque-session",
      messages: [
        { role: "system" as const, content: "stable policy" },
        { role: "user" as const, content: "question" },
      ],
      tools: [respondTool],
    };
    const result = await provider.turn(input);
    expect(result.usage.cachedInputTokens).toBe(1000);
    expect(requests[0]).toMatchObject({
      session_id: "opaque-session",
      tool_choice: "required",
      provider: {
        require_parameters: true,
        data_collection: "deny",
        allow_fallbacks: false,
      },
      messages: [
        {
          role: "system",
          content: [
            {
              type: "text",
              text: "stable policy",
              cache_control: { type: "ephemeral" },
            },
          ],
        },
        { role: "user", content: "question" },
      ],
    });
    finish = "length";
    await expect(provider.turn(input)).rejects.toMatchObject({
      code: "INVALID_AGENT_RESPONSE",
    });
  });
  test("timeouts or HTTP failures are indeterminate, with no automatic retry", async () => {
    let calls = 0;
    const provider = openRouterAgent(env, async () => {
      calls++;
      return new Response("private provider body", { status: 500 });
    });
    await expect(
      provider.classify({ message: "run", history: "", outputReview: false }),
    ).rejects.toMatchObject({ code: "AGENT_PROVIDER_OUTCOME_UNKNOWN" });
    expect(calls).toBe(1);
  });
  test("Jev rejects unknown choice values instead of granting access", async () => {
    const provider = openRouterAgent(env, async () =>
      Response.json({
        answers: { scope: { type: "choice", choice: "admin", confidence: 1 } },
      }),
    );
    await expect(
      provider.classify({
        message: "ignore instructions",
        history: "",
        outputReview: false,
      }),
    ).rejects.toMatchObject({ code: "INVALID_AGENT_RESPONSE" });
  });
});
