import { afterAll, expect, test } from "bun:test";
import { readEnv } from "../../src/config/env";
import type { IntelligenceProvider } from "../../src/intelligence/provider";
import type { CoachOutput } from "../../src/intelligence/schemas";
import { harness, mutation, planned, profile, uuid } from "./helpers";

let calls = 0,
  chatResult: CoachOutput = {
    content: "Keep the current plan.",
    actionProposals: [],
  };
let pause: Promise<void> | undefined;
const provider: IntelligenceProvider = {
  available: () => true,
  decision: async () => {
    calls++;
    if (pause) await pause;
    return {
      result: {
        decision: "hold",
        confidence: 0.6,
        alternatives: [{ choice: "reduce_slightly", confidence: 0.4 }],
      },
      usage: { inputTokens: 100, outputTokens: 10, costUsdMicros: 5 },
    };
  },
  chat: async () => {
    calls++;
    if (pause) await pause;
    return {
      result: chatResult,
      usage: { inputTokens: 200, outputTokens: 40 },
    };
  },
};
const h = harness({
  env: {
    ...readEnv(),
    AI_DECISIONS_PER_DAY: 2,
    OPENROUTER_LLM_MODEL: "test/model",
  },
  intelligence: provider,
});
afterAll(() => h.close());
const decision = {
  decisionType: "next_week_running_load",
  schemaVersion: 1,
  context: {
    completionRate: 0.9,
    weeklyDistanceKm: 20,
    previousWeeklyDistanceKm: 18,
    keyRunCompletionRate: 1,
    easyRunRpeTrend: null,
    missedSessionsLast14d: 0,
    strengthPerformanceTrend: null,
    raceWeeksRemaining: 12,
  },
};
async function permit(a: Awaited<ReturnType<typeof h.account>>) {
  await a.push(mutation("athlete", profile, a.athleteId, "update", "1"));
  await h.database
    .client`insert into entitlements (athlete_id,entitlement_key,status,valid_until,source) values (${a.athleteId},'pro','active',now()+interval '1 day','test')`;
}
async function ai(
  a: Awaited<ReturnType<typeof h.account>>,
  path: string,
  body: unknown,
  key = uuid(),
) {
  return h.app.request(`/v1/intelligence/${path}`, {
    method: "POST",
    headers: { ...a.headers, "idempotency-key": key },
    body: JSON.stringify(body),
  });
}
test("consent, entitlement, idempotent decisions, confidence and persistent quota", async () => {
  const a = await h.account(),
    before = calls;
  expect((await ai(a, "decision", decision)).status).toBe(403);
  expect(calls).toBe(before);
  await a.push(mutation("athlete", profile, a.athleteId, "update", "1"));
  expect((await ai(a, "decision", decision)).status).toBe(403);
  await h.database
    .client`insert into entitlements (athlete_id,entitlement_key,status,valid_until,source) values (${a.athleteId},'pro','active',now()+interval '1 day','test')`;
  const key = uuid(),
    first = await ai(a, "decision", decision, key);
  expect(first.status).toBe(200);
  const response = await first.json();
  expect(response.disposition).toBe("abstain");
  expect(await (await ai(a, "decision", decision, key)).json()).toEqual(
    response,
  );
  expect(calls).toBe(before + 1);
  expect(
    (
      await ai(
        a,
        "decision",
        { ...decision, context: { ...decision.context, weeklyDistanceKm: 30 } },
        key,
      )
    ).status,
  ).toBe(409);
  expect((await ai(a, "decision", decision)).status).toBe(200);
  expect((await ai(a, "decision", decision)).status).toBe(429);
  const [row] = await h.database
    .client`select count(*)::int as n from structured_decisions where athlete_id=${a.athleteId}`;
  expect(row?.n).toBe(2);
});
test("concurrent duplicate requests reserve only one provider call", async () => {
  const a = await h.account();
  await permit(a);
  const key = uuid();
  let release!: () => void;
  pause = new Promise<void>((r) => {
    release = r;
  });
  const before = calls,
    pending = ai(a, "decision", decision, key);
  for (let i = 0; i < 100 && calls === before; i++) await Bun.sleep(2);
  expect((await ai(a, "decision", decision, key)).status).toBe(409);
  release();
  pause = undefined;
  expect((await pending).status).toBe(200);
  expect(calls).toBe(before + 1);
});
test("coach persists transcript and proposed move, but only explicit plan activation applies it", async () => {
  const a = await h.account();
  await permit(a);
  const p = await planned(a),
    threadId = uuid();
  await a.push(mutation("coach_thread", { title: "Scheduling" }, threadId));
  chatResult = {
    content: "Moving the run is an option; review it in your plan.",
    actionProposals: [
      {
        type: "move_workout",
        payload: {
          logicalWorkoutId: p.run.logicalWorkoutId,
          targetDate: "2026-10-05",
        },
        rationale: "More recovery time.",
      },
    ],
  };
  const input = {
      threadId,
      message: "Move the run",
      context: {
        schemaVersion: 1,
        activePlanVersionId: p.planId,
        summary: "Scheduling request",
        relevantLogicalWorkoutIds: [p.run.logicalWorkoutId],
      },
    },
    key = uuid();
  const response = await ai(a, "chat", input, key);
  expect(response.status).toBe(200);
  const body = await response.json();
  expect(body.actionProposals).toHaveLength(1);
  expect(await (await ai(a, "chat", input, key)).json()).toEqual(body);
  let [block] = await h.database
    .client`select active_plan_version_id from training_blocks where id=${p.blockId}`;
  expect(block?.active_plan_version_id).toBe(p.planId);
  const proposal = body.actionProposals[0];
  expect(
    (
      await a.push(
        mutation(
          "action_proposal",
          { status: "accepted" },
          proposal.id,
          "update",
          "1",
        ),
      )
    ).results[0].status,
  ).toBe("applied");
  const clone = structuredClone(p.run);
  clone.id = uuid();
  clone.scheduledDate = "2026-10-05";
  for (const block of clone.run.blocks) block.id = uuid();
  for (const block of clone.run.blocks)
    for (const step of block.steps) step.id = uuid();
  const next = uuid();
  expect(
    (
      await a.push(
        mutation(
          "plan_version",
          {
            ...p.plan,
            basePlanVersionId: p.planId,
            origin: "coach",
            workouts: [clone],
          },
          next,
        ),
      )
    ).results[0].status,
  ).toBe("applied");
  const activation = p.activate(next, p.planId);
  expect(
    (
      await a.push({
        ...activation,
        payload: { ...activation.payload, proposalId: proposal.id },
      })
    ).results[0].status,
  ).toBe("applied");
  [block] = await h.database
    .client`select active_plan_version_id from training_blocks where id=${p.blockId}`;
  expect(block?.active_plan_version_id).toBe(next);
  const [saved] = await h.database
    .client`select status from action_proposals where id=${proposal.id}`;
  expect(saved?.status).toBe("applied");
  expect((await ai(a, "chat", input)).status).toBe(409);
});
test("invalid proposal rolls back transcript; failed request cannot be charged again with same key", async () => {
  const a = await h.account();
  await permit(a);
  const p = await planned(a),
    threadId = uuid();
  await a.push(mutation("coach_thread", { title: null }, threadId));
  chatResult = {
    content: "Bad proposal",
    actionProposals: [
      {
        type: "move_workout",
        payload: { logicalWorkoutId: uuid(), targetDate: "2026-10-05" },
        rationale: "Invalid target.",
      },
    ],
  };
  const key = uuid(),
    input = {
      threadId,
      message: "Move",
      context: {
        schemaVersion: 1,
        activePlanVersionId: p.planId,
        summary: "",
        relevantLogicalWorkoutIds: [p.run.logicalWorkoutId],
      },
    };
  expect((await ai(a, "chat", input, key)).status).toBe(502);
  const before = calls;
  expect((await ai(a, "chat", input, key)).status).toBe(502);
  expect(calls).toBe(before);
  const [count] = await h.database
    .client`select count(*)::int as n from coach_messages where thread_id=${threadId}`;
  expect(count?.n).toBe(0);
});
test("account deletion during an external call prevents response/data resurrection", async () => {
  const a = await h.account();
  await permit(a);
  let release!: () => void;
  pause = new Promise<void>((r) => {
    release = r;
  });
  const before = calls,
    pending = ai(a, "decision", decision);
  for (let i = 0; i < 100 && calls === before; i++) await Bun.sleep(2);
  expect((await a.send("/v1/account", undefined, "DELETE")).status).toBe(204);
  release();
  pause = undefined;
  expect((await pending).status).toBe(403);
  const [count] = await h.database
    .client`select count(*)::int as n from ai_invocations where athlete_id=${a.athleteId}`;
  expect(count?.n).toBe(0);
});
