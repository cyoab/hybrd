import { afterEach, expect, test } from "bun:test";
import type { AgentProvider, ToolCall } from "../../src/agent/provider";
import { processAgentRun, pruneAgentData } from "../../src/agent/runner";
import type { Answer, Scope } from "../../src/agent/schemas";
import { ApiError } from "../../src/api/errors";
import { readEnv } from "../../src/config/env";
import { harness, mutation, profile, uuid } from "./helpers";

const sessions: ReturnType<typeof harness>[] = [];
afterEach(async () => {
  for (const h of sessions.splice(0)) await h.close();
});
const answer: Answer = {
  content: "Keep your easy runs comfortable and review your recorded effort.",
  observations: [],
  interpretations: [],
  limitations: ["No complete HR time series was supplied."],
  recommendations: [],
  evidenceIds: [],
};
function call(name: string, input: unknown): ToolCall {
  return {
    id: uuid(),
    type: "function",
    function: { name, arguments: JSON.stringify(input) },
  };
}
async function setup(
  overrides: Partial<AgentProvider> = {},
  settings: Record<string, unknown> = {},
) {
  const invocations: { kind: string; input: unknown }[] = [];
  const legacyRequests: unknown[] = [];
  const provider: AgentProvider = {
    available: () => true,
    classify: async (input) => {
      invocations.push({ kind: "scope", input });
      return {
        result: { choice: "hybrid_training", confidence: 0.99 },
        usage: { inputTokens: 30, costUsdMicros: 2 },
      };
    },
    turn: async (input) => {
      invocations.push({ kind: "turn", input });
      return {
        calls: [call("respond", answer)],
        usage: {
          inputTokens: 1500,
          cachedInputTokens: 1200,
          cacheWriteTokens: 0,
          outputTokens: 100,
          reasoningTokens: 10,
          costUsdMicros: 100,
        },
      };
    },
    ...overrides,
  };
  const env = {
    ...readEnv(),
    AGENT_ENABLED: true,
    AGENT_MODEL: "test/agent",
    ...settings,
  };
  const h = harness({
    env,
    agent: provider,
    intelligence: {
      available: () => true,
      decision: async () => {
        throw new Error("unused");
      },
      chat: async (input) => {
        legacyRequests.push(input);
        return {
          result: { content: "Training guidance", actionProposals: [] },
          usage: {},
        };
      },
    },
  });
  sessions.push(h);
  const a = await h.account();
  const permit = async () => {
    await a.push(mutation("athlete", profile, a.athleteId, "update", "1"));
    await h.database
      .client`insert into entitlements(athlete_id,entitlement_key,status,valid_until,source) values(${a.athleteId},'pro','active',now()+interval '1 day','test')`;
  };
  const body = {
    schemaVersion: 1,
    task: "chat",
    deviceId: a.deviceId,
    message: "How should I pace an easy run?",
  };
  const create = (input: unknown = body, key = uuid()) =>
    h.app.request("/v1/agent/runs", {
      method: "POST",
      headers: { ...a.headers, "idempotency-key": key },
      body: JSON.stringify(input),
    });
  const step = () => processAgentRun(h.database.client, env, provider);
  const drain = async (id: string) => {
    for (let i = 0; i < 15; i++) {
      const run = await h.services.agent.get(a.userId, id);
      if (!["queued", "running"].includes(run.status)) return run;
      await step();
    }
    throw new Error("Run did not finish");
  };
  return {
    h,
    a,
    env,
    provider,
    invocations,
    legacyRequests,
    permit,
    body,
    create,
    step,
    drain,
  };
}
test("agent configuration, consent, entitlement, device and task gates are independent", async () => {
  const s = await setup();
  expect((await s.create()).status).toBe(403);
  await s.permit();
  expect((await s.create({ ...s.body, deviceId: uuid() })).status).toBe(403);
  const unsupported = await s.create({ ...s.body, task: "create_plan" });
  expect(unsupported.status).toBe(409);
  expect((await unsupported.json()).error.code).toBe("AGENT_TASK_NOT_ENABLED");
  const capabilities = await (await s.a.send("/v1/agent/capabilities")).json();
  expect(capabilities.tasks).toEqual({
    chat: true,
    analyze_workout: true,
    create_plan: false,
    modify_plan: false,
  });
  expect(s.invocations).toHaveLength(0);
});
test("durable creation is idempotent and serializes conversations across legacy and agent APIs", async () => {
  const s = await setup();
  await s.permit();
  const key = uuid();
  const [first, duplicate] = await Promise.all([
    s.create(s.body, key),
    s.create(s.body, key),
  ]);
  expect(first.status).toBe(202);
  expect(duplicate.status).toBe(202);
  const run = await first.json();
  expect((await duplicate.json()).id).toBe(run.id);
  expect(s.invocations).toHaveLength(0);
  expect(
    (await s.create({ ...s.body, message: "Different" }, key)).status,
  ).toBe(409);
  expect((await s.create({ ...s.body, threadId: run.threadId })).status).toBe(
    409,
  );
  expect((await s.drain(run.id)).status).toBe("succeeded");
  const replay = await (await s.create(s.body, key)).json();
  expect(replay.status).toBe("succeeded");
  expect(s.invocations.filter((i) => i.kind === "turn")).toHaveLength(1);
});
test("events replay in order and final artifacts restore without unknown sync entities", async () => {
  const s = await setup();
  await s.permit();
  const run = await (await s.create()).json();
  const done = await s.drain(run.id);
  expect(done.artifact?.content).toBe(answer.content);
  const response = await s.h.app.request(`/v1/agent/runs/${run.id}/events`, {
    headers: { ...s.a.headers, "last-event-id": "1" },
  });
  expect(response.status).toBe(200);
  expect(response.headers.get("content-type")).toContain("text/event-stream");
  const stream = await response.text();
  expect(stream).toContain("event: completed");
  const ids = [...stream.matchAll(/^id: (\d+)$/gm)].map((m) => Number(m[1]));
  expect(ids[0]).toBe(2);
  expect(new Set(ids).size).toBe(ids.length);
  const [unknown] = await s.h.database
    .client`select count(*)::int as n from sync_change_log where athlete_id=${s.a.athleteId} and entity_type like 'agent%'`;
  expect(unknown?.n).toBe(0);
  const [usage] = await s.h.database
    .client`select input_tokens,cached_input_tokens,cache_write_tokens,reasoning_tokens,cost_usd_micros from ai_invocations where athlete_id=${s.a.athleteId} and feature='agent_turn'`;
  expect(usage).toMatchObject({
    input_tokens: 1500,
    cached_input_tokens: 1200,
    cache_write_tokens: 0,
    reasoning_tokens: 10,
    cost_usd_micros: "100",
  });
});
test("cross-account runs, event streams and memories cannot be read or mutated", async () => {
  const s = await setup();
  await s.permit();
  const run = await (await s.create()).json(),
    other = await s.h.account();
  for (const path of [
    `/v1/agent/runs/${run.id}`,
    `/v1/agent/runs/${run.id}/events`,
  ])
    expect((await other.send(path)).status).toBe(404);
  expect((await other.send(`/v1/agent/runs/${run.id}/cancel`, {})).status).toBe(
    404,
  );
  const id = uuid(),
    memory = {
      expectedRevision: null,
      category: "training_preference",
      content: "Prefer incline bench",
      expiresAt: null,
    };
  expect(
    (await s.a.send(`/v1/agent/memories/${id}`, memory, "PUT")).status,
  ).toBe(200);
  expect(
    (await other.send(`/v1/agent/memories/${id}`, memory, "PUT")).status,
  ).toBe(404);
  expect(
    (await (await other.send("/v1/agent/memories")).json()).memories,
  ).toEqual([]);
});
test("scope rejection and uncertainty never reach the generative model", async () => {
  for (const scope of [
    { choice: "out_of_scope", confidence: 0.99 },
    { choice: "hybrid_training", confidence: 0.55 },
  ] as Scope[]) {
    const s = await setup({
      classify: async () => ({ result: scope, usage: {} }),
    });
    await s.permit();
    const run = await (await s.create()).json();
    const done = await s.drain(run.id);
    expect(done.status).toBe("succeeded");
    expect(done.artifact?.kind).toBe(
      scope.choice === "out_of_scope" ? "scope_redirect" : "clarification",
    );
    expect(s.invocations).toHaveLength(0);
  }
});
test("output scope review suppresses an unrelated answer before it is stored or streamed", async () => {
  const s = await setup({
    classify: async (input) => ({
      result: {
        choice: input.outputReview ? "out_of_scope" : "hybrid_training",
        confidence: 0.99,
      },
      usage: {},
    }),
    turn: async () => ({
      calls: [
        call("respond", {
          ...answer,
          content: "Unrelated answer that must not publish",
        }),
      ],
      usage: {},
    }),
  });
  await s.permit();
  const run = await (await s.create()).json();
  const done = await s.drain(run.id);
  expect(done.artifact?.kind).toBe("scope_redirect");
  const messages = await s.h.database
    .client`select content from coach_messages where athlete_id=${s.a.athleteId}`;
  expect(JSON.stringify(messages)).not.toContain("must not publish");
});
test("typed read tools and citation resolution work; unknown tools and invented references fail closed", async () => {
  let turn = 0;
  const s = await setup({
    turn: async () => ({
      calls: [
        turn++ === 0
          ? call("evidence_search", { topic: "concurrent" })
          : call("respond", {
              ...answer,
              evidenceIds: ["concurrent-training-2022"],
            }),
      ],
      usage: {},
    }),
  });
  await s.permit();
  const run = await (await s.create()).json();
  expect((await s.drain(run.id)).artifact?.citations[0]?.url).toBe(
    "https://pmc.ncbi.nlm.nih.gov/articles/PMC8891239/",
  );
  for (const badCall of [
    call("delete_account", {}),
    call("respond", { ...answer, evidenceIds: ["invented-paper"] }),
    call("respond", {
      ...answer,
      observations: [{ text: "Invented heart rate", metricRefs: ["missing"] }],
    }),
  ]) {
    s.provider.turn = async () => ({ calls: [badCall], usage: {} });
    const next = await (await s.create()).json();
    expect((await s.drain(next.id)).status).toBe("failed");
  }
});
test("bounded tool loops terminate rather than generating endlessly", async () => {
  let turns = 0;
  const s = await setup(
    {
      turn: async () => {
        turns++;
        return {
          calls: [call("evidence_search", { topic: "all" })],
          usage: {},
        };
      },
    },
    { AGENT_MAX_GENERATIVE_CALLS: 2 },
  );
  await s.permit();
  const run = await (await s.create()).json();
  const done = await s.drain(run.id);
  expect(done.errorCode).toBe("AGENT_BUDGET_EXHAUSTED");
  expect(turns).toBe(2);
});
test("only one worker claims an in-flight step and cancellation fences a late answer", async () => {
  let entered = false,
    release: (() => void) | undefined;
  const pause = new Promise<void>((r) => {
    release = r;
  });
  const s = await setup({
    classify: async () => {
      entered = true;
      await pause;
      return {
        result: { choice: "hybrid_training", confidence: 0.99 },
        usage: { inputTokens: 20 },
      };
    },
  });
  await s.permit();
  const run = await (await s.create()).json();
  const work = s.step();
  for (let i = 0; i < 100 && !entered; i++) await Bun.sleep(5);
  expect(entered).toBe(true);
  expect(await s.step()).toBe(false);
  expect((await s.a.send(`/v1/agent/runs/${run.id}/cancel`, {})).status).toBe(
    200,
  );
  release?.();
  await work;
  const cancelled = await s.h.services.agent.get(s.a.userId, run.id);
  expect(cancelled.status).toBe("cancelled");
  expect(cancelled.artifact).toBeNull();
  const [ledger] = await s.h.database
    .client`select status,input_tokens from ai_invocations where athlete_id=${s.a.athleteId}`;
  expect(ledger).toMatchObject({ status: "completed", input_tokens: 20 });
});
test("expired in-flight leases and provider transport ambiguity never automatically retry paid work", async () => {
  const s = await setup();
  await s.permit();
  const run = await (await s.create()).json();
  await s.h.database
    .client`update agent_runs set status='running',provider_pending=true,lease_token=${uuid()},lease_expires_at=now()-interval '1 second' where id=${run.id}`;
  expect((await s.drain(run.id)).status).toBe("indeterminate");
  expect(s.invocations).toHaveLength(0);
  s.provider.classify = async () => {
    throw new ApiError(502, "AGENT_PROVIDER_OUTCOME_UNKNOWN", "uncertain");
  };
  const second = await (await s.create()).json();
  expect((await s.drain(second.id)).status).toBe("indeterminate");
});
test("consent and entitlement are checked again after queued work and provider calls", async () => {
  const s = await setup();
  await s.permit();
  const run = await (await s.create()).json();
  await s.a.push(
    mutation(
      "athlete",
      { ...profile, cloudAiConsent: false },
      s.a.athleteId,
      "update",
      "2",
    ),
  );
  expect((await s.drain(run.id)).errorCode).toBe("AI_CONSENT_REQUIRED");
  expect(s.invocations).toHaveLength(0);
  await s.a.push(mutation("athlete", profile, s.a.athleteId, "update", "3"));
  const next = await (await s.create()).json();
  s.provider.classify = async () => {
    await s.h.database
      .client`update entitlements set status='revoked' where athlete_id=${s.a.athleteId}`;
    return {
      result: { choice: "hybrid_training", confidence: 0.99 },
      usage: {},
    };
  };
  expect((await s.drain(next.id)).errorCode).toBe("ENTITLEMENT_REQUIRED");
});
test("memory corrections cancel cached runs; forgetting removes payload and excludes old conversational context", async () => {
  const s = await setup();
  await s.permit();
  const id = uuid(),
    memory = {
      expectedRevision: null,
      category: "training_preference",
      content: "Prefer dumbbell incline",
      expiresAt: null,
    };
  expect(
    (await s.a.send(`/v1/agent/memories/${id}`, memory, "PUT")).status,
  ).toBe(200);
  const run = await (await s.create()).json();
  await s.step();
  const [checkpoint] = await s.h.database
    .client`select checkpoint from agent_runs where id=${run.id}`;
  expect(JSON.stringify(checkpoint)).toContain("Prefer dumbbell incline");
  const forgotten = await s.h.app.request(`/v1/agent/memories/${id}`, {
    method: "DELETE",
    headers: { ...s.a.headers, "if-match": "1" },
  });
  expect(forgotten.status).toBe(204);
  expect((await s.h.services.agent.get(s.a.userId, run.id)).status).toBe(
    "cancelled",
  );
  const [cleared] = await s.h.database
    .client`select checkpoint from agent_runs where id=${run.id}`;
  expect(cleared?.checkpoint).toBeNull();
  expect((await s.h.services.agent.memories(s.a.userId)).memories).toHaveLength(
    0,
  );
  const next = await (
    await s.create({ ...s.body, threadId: run.threadId })
  ).json();
  await s.drain(next.id);
  expect(
    JSON.stringify(s.invocations.filter((i) => i.kind === "turn")),
  ).not.toContain("Prefer dumbbell incline");
});
test("analysis is bound to actual revisions and reports stale artifacts after correction", async () => {
  const s = await setup();
  await s.permit();
  const resultId = uuid();
  const pushed = await s.a.push(
    mutation(
      "workout_result",
      {
        discipline: "running",
        plannedWorkoutId: null,
        logicalWorkoutId: null,
        trainingDate: "2026-09-25",
        timezone: "America/Monterrey",
        durationS: 1800,
        completionStatus: "completed",
        sourceType: "manual",
        run: { distanceM: 5000, durationS: 1800, avgHrBpm: 140, segments: [] },
      },
      resultId,
    ),
  );
  expect(pushed.results[0].status).toBe("applied");
  const input = {
    ...s.body,
    task: "analyze_workout",
    workoutResultId: resultId,
    expectedWorkoutRevision: "1",
  };
  expect(
    (await s.create({ ...input, expectedWorkoutRevision: "9" })).status,
  ).toBe(409);
  s.provider.turn = async () => ({
    calls: [
      call("respond", {
        ...answer,
        observations: [
          {
            text: "Your elapsed mean pace was 360 seconds per kilometer.",
            metricRefs: [`${resultId}@1:run.meanPace`],
          },
        ],
      }),
    ],
    usage: {},
  });
  const run = await (await s.create(input)).json();
  const done = await s.drain(run.id);
  expect(done.status).toBe("succeeded");
  expect(done.artifact?.analyzedResult).toEqual({
    id: resultId,
    revision: "1",
  });
  expect(done.artifactStale).toBe(false);
  await s.h.database
    .client`update workout_results set revision=revision+1 where id=${resultId}`;
  expect((await s.h.services.agent.get(s.a.userId, run.id)).artifactStale).toBe(
    true,
  );
});
test("expired event replay fails explicitly; export and account deletion cover agent data", async () => {
  const s = await setup();
  await s.permit();
  const run = await (await s.create()).json();
  await s.drain(run.id);
  await s.h.database
    .client`update agent_events set created_at=now()-interval '8 days' where run_id=${run.id}`;
  await pruneAgentData(s.h.database.client);
  const replay = await s.a.send(`/v1/agent/runs/${run.id}/events`);
  expect(replay.status).toBe(409);
  expect((await replay.json()).error.code).toBe("AGENT_EVENT_REPLAY_EXPIRED");
  const exported = await s.h.services.exportAccount(s.a.userId);
  expect(JSON.stringify(exported.agent)).toContain(run.id);
  await s.h.database.client`delete from auth_user where id=${s.a.userId}`;
  const [left] = await s.h.database
    .client`select count(*)::int as n from agent_runs where id=${run.id}`;
  expect(left?.n).toBe(0);
});

test("context and recent-workout tools return only bounded owned training data", async () => {
  let step = 0;
  const s = await setup({
    turn: async () => ({
      calls:
        step++ === 0
          ? [
              call("athlete_context", {}),
              call("recent_workouts", { discipline: "all", limit: 5 }),
            ]
          : [call("respond", answer)],
      usage: {},
    }),
  });
  await s.permit();
  const run = await (await s.create()).json();
  const done = await s.drain(run.id);
  expect(done).toMatchObject({ status: "succeeded", errorCode: null });
  const events = await s.h.services.agent.events(s.a.userId, run.id, "0");
  expect(
    events.events
      .filter((e) => e.type === "tool_status")
      .map((e) => e.data.tool),
  ).toEqual(["athlete_context", "recent_workouts"]);
});

test("foreign workout tool requests cannot turn into model context", async () => {
  const s = await setup({
    turn: async () => ({
      calls: [call("workout_details", { resultId: uuid() })],
      usage: {},
    }),
  });
  await s.permit();
  const run = await (await s.create()).json();
  expect((await s.drain(run.id)).errorCode).toBe("REFERENCE_UNAVAILABLE");
});

test("memory updates require the current revision and expired constraints stay out of prompts", async () => {
  const s = await setup();
  await s.permit();
  const id = uuid(),
    body = {
      expectedRevision: null,
      category: "temporary_constraint",
      content: "Temporary travel constraint",
      expiresAt: new Date(Date.now() + 60000).toISOString(),
    };
  expect((await s.a.send(`/v1/agent/memories/${id}`, body, "PUT")).status).toBe(
    200,
  );
  expect(
    (
      await s.a.send(
        `/v1/agent/memories/${id}`,
        { ...body, content: "Stale edit" },
        "PUT",
      )
    ).status,
  ).toBe(409);
  const replacement = await s.a.send(
    `/v1/agent/memories/${id}`,
    {
      ...body,
      expectedRevision: "1",
      content: "Updated temporary travel constraint",
    },
    "PUT",
  );
  expect((await replacement.json()).revision).toBe("2");
  await s.h.database
    .client`update athlete_memories set expires_at=now()-interval '1 second' where id=${id}`;
  const run = await (await s.create()).json();
  await s.drain(run.id);
  expect(JSON.stringify(s.invocations)).not.toContain("travel constraint");
});

test("account deletion during a provider call never resurrects records", async () => {
  const s = await setup();
  await s.permit();
  const run = await (await s.create()).json();
  s.provider.classify = async () => {
    await s.h.database.client`delete from auth_user where id=${s.a.userId}`;
    return {
      result: { choice: "hybrid_training", confidence: 0.99 },
      usage: {},
    };
  };
  await s.step();
  const [count] = await s.h.database
    .client`select count(*)::int as n from agent_runs where id=${run.id}`;
  expect(count?.n).toBe(0);
  const [usage] = await s.h.database
    .client`select count(*)::int as n from ai_invocations where athlete_id=${s.a.athleteId}`;
  expect(usage?.n).toBe(0);
});

test("legacy coaching respects agent conversation locks and forgotten-context boundaries", async () => {
  const s = await setup();
  await s.permit();
  const run = await (
    await s.create({
      ...s.body,
      message: "Remember my temporary travel limitation",
    })
  ).json();
  const legacy = () =>
    s.h.app.request("/v1/intelligence/chat", {
      method: "POST",
      headers: { ...s.a.headers, "idempotency-key": uuid() },
      body: JSON.stringify({
        threadId: run.threadId,
        message: "Give training guidance",
        context: { schemaVersion: 1, activePlanVersionId: null, summary: "" },
      }),
    });
  const busy = await legacy();
  expect(busy.status).toBe(409);
  expect((await busy.json()).error.code).toBe("THREAD_BUSY");
  const memoryId = uuid();
  await s.a.send(
    `/v1/agent/memories/${memoryId}`,
    {
      expectedRevision: null,
      category: "temporary_constraint",
      content: "Temporary travel limitation",
      expiresAt: null,
    },
    "PUT",
  );
  expect((await legacy()).status).toBe(200);
  expect(JSON.stringify(s.legacyRequests)).not.toContain("travel limitation");
});

test("a live SSE connection observes cancellation and closes with the durable event", async () => {
  const s = await setup();
  await s.permit();
  const run = await (await s.create()).json();
  const response = await s.a.send(`/v1/agent/runs/${run.id}/events`);
  expect(response.status).toBe(200);
  const transcript = response.text();
  await s.a.send(`/v1/agent/runs/${run.id}/cancel`, {});
  const text = await transcript;
  expect(text).toContain("event: status");
  expect(text).toContain("event: cancelled");
  expect(text).not.toContain("event: completed");
});
