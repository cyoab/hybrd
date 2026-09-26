import { afterEach, expect, test } from "bun:test";
import type { AgentProvider, ToolCall } from "../../src/agent/provider";
import { processAgentRun } from "../../src/agent/runner";
import { Blueprint, WorkoutTemplate } from "../../src/agent/v2-schemas";
import { catalogId } from "../../src/catalog/data";
import { readEnv } from "../../src/config/env";
import { hash } from "../../src/db/store";
import { harness, mutation, preferences, profile, uuid } from "./helpers";

const sessions: ReturnType<typeof harness>[] = [];
afterEach(async () => {
  for (const h of sessions.splice(0)) await h.close();
});
const answer = {
  content:
    "Your requested training changes are ready. Review the action receipt for their status.",
  observations: [],
  interpretations: [],
  limitations: [],
  recommendations: [],
  evidenceIds: ["concurrent-training-2022"],
};
const call = (name: string, args: unknown): ToolCall => ({
  id: uuid(),
  type: "function",
  function: { name, arguments: JSON.stringify(args) },
});
const running = () =>
  WorkoutTemplate.parse({
    key: "easy",
    discipline: "running",
    title: "Easy run",
    workoutType: "easy",
    purpose: "Aerobic base",
    priority: "supporting",
    estimatedDurationS: 1800,
    instructions: null,
    run: {
      primaryTargetType: "rpe",
      notes: null,
      blocks: [
        {
          repeatCount: 1,
          label: null,
          steps: [
            { stepKind: "steady", durationS: 1800, rpeMin: 3, rpeMax: 4 },
          ],
        },
      ],
    },
  });
const strength = () =>
  WorkoutTemplate.parse({
    key: "strength",
    discipline: "strength",
    title: "Strength",
    workoutType: "full_body",
    purpose: "Maintain strength",
    priority: "key",
    estimatedDurationS: 2400,
    instructions: null,
    strength: {
      sessionFocus: "upper",
      notes: null,
      exercises: [
        {
          exerciseId: catalogId(3, 11),
          supersetKey: null,
          substitutionAllowed: true,
          sets: [
            {
              setKind: "working",
              repsMin: 6,
              repsMax: 8,
              rirMin: 2,
              rirMax: 3,
              restS: 120,
            },
          ],
          substitutions: [],
        },
      ],
    },
  });
const blueprint = () =>
  Blueprint.parse({
    schemaVersion: 1,
    name: "Concurrent base",
    phase: "build",
    rationale:
      "Balance endurance and resistance work with recovery opportunities.",
    evidenceIds: ["concurrent-training-2022"],
    templates: [running(), strength()],
    sessions: [
      { templateKey: "easy", date: "2026-10-02" },
      { templateKey: "strength", date: "2026-10-03" },
      { templateKey: "easy", date: "2026-10-09" },
      { templateKey: "strength", date: "2026-10-10" },
    ],
  });
async function setup() {
  let stage: { name: string; args: unknown } = {
    name: "stage_plan",
    args: blueprint(),
  };
  let beforeReview: (() => Promise<void>) | undefined;
  const provider: AgentProvider = {
    available: () => true,
    classify: async (input) => {
      if (input.outputReview) await beforeReview?.();
      return {
        result: { choice: "hybrid_training", confidence: 0.99 },
        usage: { inputTokens: 10 },
      };
    },
    turn: async ({ messages }) => ({
      calls: [
        messages.some(
          (m) => m.role === "tool" && m.content?.includes('"validated"'),
        ) ||
        messages.some(
          (m) => m.role === "tool" && m.content?.includes('"staged"'),
        )
          ? call(
              "respond",
              stage.name === "stage_plan" || stage.name === "stage_plan_edit"
                ? answer
                : { ...answer, evidenceIds: [] },
            )
          : call(stage.name, stage.args),
      ],
      usage: { inputTokens: 100, outputTokens: 30 },
    }),
  };
  const env = {
    ...readEnv(),
    AGENT_ENABLED: true,
    AGENT_MODEL: "test/agent",
    AI_CHATS_PER_DAY: 100,
    AI_REQUESTS_PER_MINUTE: 100,
  };
  const h = harness({ env, agent: provider });
  sessions.push(h);
  const a = await h.account();
  await a.push(
    mutation("athlete", profile, a.athleteId, "update", "1"),
    mutation("training_preferences", preferences, a.athleteId),
    ...Array.from({ length: 7 }, (_, i) =>
      mutation("availability_rule", {
        dayOfWeek: i + 1,
        available: true,
        maxSessions: 2,
        minSessionMinutes: 10,
        maxSessionMinutes: 120,
        preference: "neutral",
      }),
    ),
    ...Array.from({ length: 22 }, (_, i) =>
      mutation("athlete_equipment", {
        equipmentId: catalogId(1, i),
        available: true,
      }),
    ),
  );
  await h.database
    .client`insert into entitlements(athlete_id,entitlement_key,status,valid_until,source) values(${a.athleteId},'pro','active',now()+interval '1 day','test')`;
  const manifest = {
    deviceId: a.deviceId,
    surface: "phone",
    pairedDeviceId: null,
    appBuild: "test",
    executableVersion: 2,
    prescriptionSchemaVersion: 1,
    maxExpandedSteps: 2000,
    maxResultSegments: 500,
    completion: ["duration", "distance", "manual"],
    richStrength: true,
    deviceActions: ["start", "pause", "resume", "lap", "finish"],
  };
  expect(
    (await a.send("/v1/agent/v2/device-manifest", manifest, "PUT")).status,
  ).toBe(200);
  const context = () => h.services.agent.contextV2(a.userId, null);
  const create = async (input: unknown, key = uuid()) => {
    const r = await h.app.request("/v1/agent/v2/runs", {
      method: "POST",
      headers: { ...a.headers, "idempotency-key": key },
      body: JSON.stringify(input),
    });
    const body = await r.json();
    return { status: r.status, body, key };
  };
  const input = async (
    task = "create_plan",
    mode = "apply",
    blockId: string | null = null,
    planId: string | null = null,
  ) => {
    const c = await context();
    return {
      schemaVersion: 2,
      deviceId: a.deviceId,
      task,
      message: "Create and start a complete two week hybrid plan.",
      mutation: {
        contextToken: c.contextToken,
        trainingBlockId: blockId,
        expectedActivePlanVersionId: planId,
        expectedProfileRevision: c.profileRevision,
        outboxDrained: true,
        protectedLogicalWorkoutIds: [],
        mode,
        startDate: "2026-10-01",
        endDate: "2026-10-14",
        operations: [
          "move",
          "replace_exercise",
          "replace_workout",
          "remove",
          "add",
        ],
        allowRecurringPreference: true,
      },
    };
  };
  const step = () => processAgentRun(h.database.client, env, provider);
  const drain = async (id: string) => {
    for (let i = 0; i < 15; i++) {
      const r = await h.services.agent.getV2(a.userId, id);
      if (!["queued", "running"].includes(r.status)) return r;
      await step();
    }
    throw new Error("unfinished");
  };
  const generate = async (mode = "apply") => {
    stage = { name: "stage_plan", args: blueprint() };
    const r = await create(await input("create_plan", mode));
    expect(r.status).toBe(202);
    const run = await drain(r.body.id);
    expect(run.errorCode).toBeNull();
    expect(run.action).not.toBeNull();
    return run;
  };
  return {
    h,
    a,
    manifest,
    context,
    create,
    input,
    step,
    drain,
    generate,
    setStage: (name: string, args: unknown) => {
      stage = { name, args };
    },
    beforeReview: (f: () => Promise<void>) => {
      beforeReview = f;
    },
  };
}

test("v1 negotiation stays read-only; v2 creates a complete canonical plan and recovers by request key", async () => {
  const s = await setup();
  const v1 = await (await s.a.send("/v1/agent/capabilities")).json();
  expect(v1.schemaVersion).toBe(1);
  expect(v1.tasks.create_plan).toBe(false);
  const r = await s.create(await s.input());
  const run = await s.drain(r.body.id);
  expect(run.errorCode).toBeNull();
  expect(run.status).toBe("succeeded");
  expect(run.action?.lifecycle).toBe("applied");
  const workouts = await s.h.database
    .client`select * from planned_workouts where plan_version_id=${run.action!.planVersionId}`;
  expect(workouts).toHaveLength(4);
  expect(new Set(workouts.map((w) => w.id)).size).toBe(4);
  expect((await s.h.services.agent.lookupV2(s.a.userId, r.key)).id).toBe(
    run.id,
  );
  // The exact stored request, including its original context token, is replayable after commit.
  const [stored] = await s.h.database
    .client`select request from agent_runs where id=${run.id}`;
  expect((await s.create(stored!.request, r.key)).body.id).toBe(run.id);
  expect(
    (await s.h.services.agent.lookupV2(s.a.userId, r.key, true)).status,
  ).toBe("succeeded");
  expect(
    (await s.h.services.agent.listV2(s.a.userId, null)).runs.map((x) => x.id),
  ).toContain(run.id);
  const foreign = await s.h.account();
  expect((await foreign.send(`/v1/agent/v2/runs/${run.id}`)).status).toBe(404);
});

test("draft generation never activates a block and Undo rejects its draft", async () => {
  const s = await setup(),
    run = await s.generate("draft"),
    a = run.action!;
  expect(a.lifecycle).toBe("draft");
  const [b] = await s.h.database
    .client`select active_plan_version_id from training_blocks where id=${a.trainingBlockId}`;
  expect(b!.active_plan_version_id).toBeNull();
  const c = await s.context();
  const undone = await s.h.services.agent.undoV2(s.a.userId, a.id, uuid(), {
    expectedActivePlanVersionId: null,
    contextToken: c.contextToken,
    outboxDrained: true,
    protectedLogicalWorkoutIds: [],
    deviceId: s.a.deviceId,
  });
  expect(undone.lifecycle).toBe("undone");
});

test("recurring incline preference and future substitutions commit atomically; Undo preserves later unrelated edits", async () => {
  const s = await setup(),
    initial = await s.generate(),
    a = initial.action!;
  const [w] = await s.h.database
    .client`select logical_workout_id from planned_workouts where plan_version_id=${a.planVersionId} and discipline='strength' order by scheduled_date`;
  s.setStage("stage_plan_edit", {
    rationale: "Use the athlete's preferred horizontal press.",
    evidenceIds: ["acsm-resistance-2026"],
    operations: [
      {
        kind: "replace_exercise",
        logicalWorkoutId: w!.logical_workout_id,
        fromExerciseId: catalogId(3, 11),
        toExerciseId: catalogId(3, 28),
      },
    ],
    recurringPreference: {
      fromExerciseId: catalogId(3, 11),
      toExerciseId: catalogId(3, 28),
    },
  });
  const edit = await s.create(
      await s.input("modify_plan", "apply", a.trainingBlockId, a.planVersionId),
    ),
    edited = await s.drain(edit.body.id);
  expect(edited.errorCode).toBeNull();
  const receipt = edited.action!;
  const sets = await s.h.database
    .client`select e.exercise_id from strength_exercise_prescriptions e join planned_workouts w on w.id=e.planned_workout_id where w.plan_version_id=${receipt.planVersionId}`;
  expect(sets.map((e) => e.exercise_id)).toEqual([
    catalogId(3, 28),
    catalogId(3, 28),
  ]);
  const [run] = await s.h.database
    .client`select logical_workout_id from planned_workouts where plan_version_id=${receipt.planVersionId} and discipline='running' order by scheduled_date`;
  s.setStage("stage_plan_edit", {
    rationale: "Move an easy run one day.",
    evidenceIds: ["concurrent-training-2022"],
    operations: [
      {
        kind: "move",
        logicalWorkoutId: run!.logical_workout_id,
        date: "2026-10-04",
      },
    ],
    recurringPreference: null,
  });
  const move = await s.create(
      await s.input(
        "modify_plan",
        "apply",
        a.trainingBlockId,
        receipt.planVersionId,
      ),
    ),
    moved = await s.drain(move.body.id);
  expect(moved.errorCode).toBeNull();
  const c = await s.context(),
    key = uuid(),
    body = {
      expectedActivePlanVersionId: moved.action!.planVersionId,
      contextToken: c.contextToken,
      outboxDrained: true,
      protectedLogicalWorkoutIds: [],
      deviceId: s.a.deviceId,
    };
  const undo = await s.h.services.agent.undoV2(
    s.a.userId,
    receipt.id,
    key,
    body,
  );
  expect(undo.undoneByPlanVersionId).not.toBeNull();
  expect(
    (await s.h.services.agent.undoV2(s.a.userId, receipt.id, key, body))
      .undoneByPlanVersionId,
  ).toBe(undo.undoneByPlanVersionId);
  const [kept] = await s.h.database
    .client`select scheduled_date::text from planned_workouts where plan_version_id=${undo.undoneByPlanVersionId!} and logical_workout_id=${run!.logical_workout_id}`;
  expect(kept!.scheduled_date).toBe("2026-10-04");
  expect(
    await s.h.database
      .client`select * from agent_exercise_rules where athlete_id=${s.a.athleteId}`,
  ).toHaveLength(0);
});

test("stale context, unsupported devices and unauthorized operations fail without writes", async () => {
  const s = await setup(),
    input = await s.input();
  await s.a.push(
    mutation("athlete_goal", {
      discipline: "running",
      goalType: "fitness",
      status: "active",
    }),
  );
  expect((await s.create(input)).body.error.code).toBe("AGENT_CONTEXT_CHANGED");
  await s.h.services.agent.putManifest(s.a.userId, {
    ...s.manifest,
    maxResultSegments: 1,
  });
  const b = blueprint();
  b.templates[0] = running();
  if (b.templates[0].discipline === "running")
    b.templates[0].run.blocks[0]!.repeatCount = 2;
  s.setStage("stage_plan", b);
  const r = await s.create(await s.input()),
    run = await s.drain(r.body.id);
  expect(run.status).toBe("failed");
  expect(run.action).toBeNull();
  expect(
    await s.h.database
      .client`select * from plan_versions where athlete_id=${s.a.athleteId}`,
  ).toHaveLength(0);
});

test("completion failure rolls back plan, receipt, block and sync side effects", async () => {
  const s = await setup();
  const r = await s.create(await s.input());
  s.beforeReview(async () => {
    await s.h.database
      .client`update agent_runs set invocation_id=${uuid()} where id=${r.body.id}`;
  });
  const run = await s.drain(r.body.id);
  expect(run.status).toBe("failed");
  expect(run.action).toBeNull();
  expect(
    await s.h.database
      .client`select id from training_blocks where athlete_id=${s.a.athleteId}`,
  ).toHaveLength(0);
  expect(
    await s.h.database
      .client`select id from agent_actions where athlete_id=${s.a.athleteId}`,
  ).toHaveLength(0);
});

test("automatic learning requires separate opt-in, exact provenance and revocation removes learned context", async () => {
  const s = await setup();
  s.setStage("stage_memories", {
    memories: [
      {
        category: "communication",
        content: "I prefer brief coaching",
        sourceQuote: "I prefer brief coaching",
        confidence: 1,
        expiresAt: null,
      },
    ],
  });
  const settings = await s.h.services.agent.settingsV2(s.a.userId);
  expect(settings.enabled).toBe(false);
  const input = {
    schemaVersion: 2,
    deviceId: s.a.deviceId,
    task: "chat",
    message: "I prefer brief coaching",
  };
  const rejected = await s.create(input);
  expect((await s.drain(rejected.body.id)).errorCode).toBe(
    "AGENT_TOOL_NOT_ALLOWED",
  );
  await s.h.services.agent.settingsV2(s.a.userId, {
    enabled: true,
    expectedRevision: settings.revision,
  });
  const r = await s.create(input),
    run = await s.drain(r.body.id);
  expect(run.errorCode).toBeNull();
  expect(run.learnedMemoryIds).toHaveLength(1);
  const mem = (await s.h.services.agent.memoriesV2(s.a.userId)).memories[0]!;
  expect(mem.sourceRunId).toBe(run.id);
  expect(mem.sourceMessageId).not.toBeNull();
  expect(mem.sourceQuote).toBe(mem.content);
  const pending = await s.create(input);
  await s.h.services.agent.forgetMemory(s.a.userId, mem.id, mem.revision);
  expect(
    (await s.h.services.agent.getV2(s.a.userId, pending.body.id)).status,
  ).toBe("cancelled");
  const state = await s.h.services.agent.settingsV2(s.a.userId);
  await s.h.services.agent.settingsV2(s.a.userId, {
    enabled: false,
    expectedRevision: state.revision,
  });
  expect(
    (await s.h.services.agent.memoriesV2(s.a.userId)).memories,
  ).toHaveLength(0);
});

test("device actions remain pending until an exact, unexpired idempotent receipt", async () => {
  const s = await setup();
  s.setStage("stage_device_action", {});
  const recordingId = uuid();
  const r = await s.create({
      schemaVersion: 2,
      deviceId: s.a.deviceId,
      task: "device_action",
      message: "Pause my current recording",
      native: {
        deviceId: s.a.deviceId,
        action: "pause",
        recordingId,
        plannedWorkoutId: null,
        expectedLocalState: "recording",
      },
    }),
    run = await s.drain(r.body.id);
  expect(run.errorCode).toBeNull();
  expect(run.deviceChallenge?.status).toBe("pending");
  const c = run.deviceChallenge!;
  const claimed = await s.h.services.agent.claimChallengeV2(
    s.a.userId,
    c.id,
    uuid(),
    { deviceId: s.a.deviceId, digest: c.digest, recordingId },
  );
  const key = uuid(),
    body = {
      deviceId: s.a.deviceId,
      digest: c.digest,
      claimToken: claimed.claimToken,
      recordingId,
      status: "executed",
      localState: "paused",
      reason: null,
    };
  expect(
    (await s.h.services.agent.ackV2(s.a.userId, c.id, key, body)).status,
  ).toBe("executed");
  expect(
    (await s.h.services.agent.ackV2(s.a.userId, c.id, key, body)).status,
  ).toBe("executed");
  await expect(
    s.h.services.agent.ackV2(s.a.userId, c.id, uuid(), {
      ...body,
      recordingId: uuid(),
    }),
  ).rejects.toMatchObject({ code: "DEVICE_ACK_CONFLICT" });
});

test("analysis packets enforce checksum, result revision, provenance, independent interval series and no GPS", async () => {
  const s = await setup(),
    run = await s.generate(),
    action = run.action!;
  const [w] = await s.h.database
    .client`select id,logical_workout_id from planned_workouts where plan_version_id=${action.planVersionId} and discipline='running' limit 1`;
  const resultId = uuid();
  const pushed = await s.a.push(
    mutation(
      "workout_result",
      {
        plannedWorkoutId: w!.id,
        logicalWorkoutId: w!.logical_workout_id,
        discipline: "running",
        trainingDate: "2026-10-02",
        timezone: "America/Monterrey",
        startedAt: "2026-10-02T12:00:00Z",
        endedAt: "2026-10-02T12:30:00Z",
        durationS: 1800,
        completionStatus: "completed",
        sourceType: "manual",
        run: {
          durationS: 1800,
          distanceM: 4000,
          movingDurationS: 1700,
          segments: [],
        },
      },
      resultId,
    ),
  );
  expect(pushed.results[0].status).toBe("applied");
  const unsigned = {
    schemaVersion: 1,
    algorithmVersion: "ios-test-1",
    deviceId: s.a.deviceId,
    resultId,
    resultRevision: "1",
    plannedWorkoutId: w!.id,
    recordingId: uuid(),
    source: "iphone",
    startedAt: "2026-10-02T12:00:00Z",
    endedAt: "2026-10-02T12:30:00Z",
    elapsedDurationS: 1800,
    activeDurationS: 1750,
    movingDurationS: 1700,
    consentVersion: 1,
    units: "seconds_meters_bpm",
    coverage: {
      heartRate: "summary_only",
      omissions: ["No HR trace captured"],
    },
    heartRate: [],
    boundaries: [],
  };
  const falseCoverage = {
    ...unsigned,
    coverage: { heartRate: "complete", omissions: [] },
    heartRate: [
      { elapsedS: 0, bpm: 120 },
      { elapsedS: 1800, bpm: 140 },
    ],
  };
  await expect(
    s.h.services.agent.packetV2(s.a.userId, {
      ...falseCoverage,
      checksum: hash(falseCoverage),
    }),
  ).rejects.toMatchObject({ code: "ANALYSIS_COVERAGE_INVALID" });
  const packet = { ...unsigned, checksum: hash(unsigned) };
  expect((await s.h.services.agent.packetV2(s.a.userId, packet)).status).toBe(
    "stored",
  );
  expect((await s.h.services.agent.packetV2(s.a.userId, packet)).status).toBe(
    "stored",
  );
  await expect(
    s.h.services.agent.packetV2(s.a.userId, {
      ...packet,
      checksum: "0".repeat(64),
    }),
  ).rejects.toMatchObject({ code: "ANALYSIS_CHECKSUM_MISMATCH" });
  await expect(
    s.h.services.agent.packetV2(s.a.userId, { ...packet, resultRevision: "2" }),
  ).rejects.toMatchObject({ code: "WORKOUT_REVISION_CONFLICT" });
  expect(
    (
      await s.a.send(
        "/v1/agent/v2/analysis-packet",
        { ...packet, latitude: 2 },
        "PUT",
      )
    ).status,
  ).toBe(400);
});

test("draft acceptance is idempotent, checks fresh state and needs no provider call", async () => {
  const s = await setup(),
    r = await s.generate("draft"),
    a = r.action!,
    c = await s.context(),
    key = uuid();
  const body = {
    expectedActivePlanVersionId: null,
    contextToken: c.contextToken,
    deviceId: s.a.deviceId,
    outboxDrained: true,
    protectedLogicalWorkoutIds: [],
  };
  const applied = await s.h.services.agent.applyV2(s.a.userId, a.id, key, body);
  expect(applied.lifecycle).toBe("applied");
  expect(applied.planRevision).toBe("2");
  expect(
    (await s.h.services.agent.applyV2(s.a.userId, a.id, key, body)).id,
  ).toBe(a.id);
  const [count] = await s.h.database
    .client`select count(*)::int as n from ai_invocations where athlete_id=${s.a.athleteId}`;
  expect(count!.n).toBe(4);
  const after = await s.context();
  const undo = await s.h.services.agent.undoV2(s.a.userId, a.id, uuid(), {
    ...body,
    contextToken: after.contextToken,
    expectedActivePlanVersionId: a.planVersionId,
  });
  expect(undo.lifecycle).toBe("undone");
});

test("provider review cannot publish writes after context changes or cancellation", async () => {
  const s = await setup(),
    r = await s.create(await s.input());
  s.beforeReview(async () => {
    await s.a.push(
      mutation("athlete_goal", {
        discipline: "running",
        goalType: "fitness",
        status: "active",
      }),
    );
  });
  const failed = await s.drain(r.body.id);
  expect(failed.errorCode).toBe("AGENT_CONTEXT_CHANGED");
  expect(failed.action).toBeNull();
});

test("recorded historical prescriptions survive edits, reject Undo removal and allow unrelated later edits", async () => {
  const s = await setup(),
    initial = await s.generate(),
    a = initial.action!;
  const rows = await s.h.database
    .client`select id,logical_workout_id from planned_workouts where plan_version_id=${a.planVersionId} and discipline='running' order by scheduled_date`;
  const first = rows[0]!,
    other = rows[1]!;
  s.setStage("stage_plan_edit", {
    rationale: "Move the requested run.",
    evidenceIds: ["concurrent-training-2022"],
    operations: [
      {
        kind: "move",
        logicalWorkoutId: first.logical_workout_id,
        date: "2026-10-04",
      },
    ],
    recurringPreference: null,
  });
  const change = await s.create(
      await s.input("modify_plan", "apply", a.trainingBlockId, a.planVersionId),
    ),
    moved = await s.drain(change.body.id);
  expect(moved.errorCode).toBeNull();
  const actual = {
    plannedWorkoutId: first.id,
    logicalWorkoutId: first.logical_workout_id,
    discipline: "running",
    trainingDate: "2026-10-02",
    timezone: "America/Monterrey",
    durationS: 1800,
    completionStatus: "completed",
    sourceType: "manual",
    run: { distanceM: 4000, durationS: 1800, segments: [] },
  };
  expect(
    (await s.a.push(mutation("workout_result", actual))).results[0].status,
  ).toBe("applied");
  const c = await s.context();
  await expect(
    s.h.services.agent.undoV2(s.a.userId, moved.action!.id, uuid(), {
      expectedActivePlanVersionId: moved.action!.planVersionId,
      contextToken: c.contextToken,
      deviceId: s.a.deviceId,
      outboxDrained: true,
      protectedLogicalWorkoutIds: [],
    }),
  ).rejects.toMatchObject({ code: "COMPLETED_WORKOUT_IMMUTABLE" });
  s.setStage("stage_plan_edit", {
    rationale: "Move the other run.",
    evidenceIds: ["concurrent-training-2022"],
    operations: [
      {
        kind: "move",
        logicalWorkoutId: other.logical_workout_id,
        date: "2026-10-11",
      },
    ],
    recurringPreference: null,
  });
  const next = await s.create(
    await s.input(
      "modify_plan",
      "apply",
      a.trainingBlockId,
      moved.action!.planVersionId,
    ),
  );
  expect((await s.drain(next.body.id)).errorCode).toBeNull();
  const [original] = await s.h.database
    .client`select scheduled_date::text from planned_workouts where id=${String(first.id)}`;
  expect(original!.scheduled_date).toBe("2026-10-02");
});

test("Undo refuses to overwrite later edits to the same logical workout", async () => {
  const s = await setup(),
    initial = await s.generate(),
    a = initial.action!;
  const [w] = await s.h.database
    .client`select logical_workout_id from planned_workouts where plan_version_id=${a.planVersionId} and discipline='running' order by scheduled_date`;
  let head = a.planVersionId;
  const receipts = [];
  for (const date of ["2026-10-04", "2026-10-05"]) {
    s.setStage("stage_plan_edit", {
      rationale: "Move requested run.",
      evidenceIds: ["concurrent-training-2022"],
      operations: [
        { kind: "move", logicalWorkoutId: w!.logical_workout_id, date },
      ],
      recurringPreference: null,
    });
    const r = await s.create(
        await s.input("modify_plan", "apply", a.trainingBlockId, head),
      ),
      run = await s.drain(r.body.id);
    expect(run.errorCode).toBeNull();
    receipts.push(run.action!);
    head = run.action!.planVersionId;
  }
  const c = await s.context();
  await expect(
    s.h.services.agent.undoV2(s.a.userId, receipts[0]!.id, uuid(), {
      expectedActivePlanVersionId: head,
      contextToken: c.contextToken,
      deviceId: s.a.deviceId,
      outboxDrained: true,
      protectedLogicalWorkoutIds: [],
    }),
  ).rejects.toMatchObject({ code: "UNDO_PLAN_CONFLICT" });
});

test("an offline or incompatible Watch does not inherit phone capabilities; expired commands cannot execute", async () => {
  const s = await setup(),
    watch = uuid();
  await s.h.services.registerDevice(s.a.userId, watch, {
    appVersion: "test",
    pushEnabled: false,
    pushEnvironment: "sandbox",
  });
  const body = {
    schemaVersion: 2,
    deviceId: s.a.deviceId,
    task: "device_action",
    message: "Pause the Watch recording",
    native: {
      deviceId: watch,
      action: "pause",
      recordingId: uuid(),
      plannedWorkoutId: null,
      expectedLocalState: "recording",
    },
  };
  expect((await s.create(body)).body.error.code).toBe(
    "DEVICE_CAPABILITIES_REQUIRED",
  );
  await s.h.services.agent.putManifest(s.a.userId, {
    ...s.manifest,
    deviceId: watch,
    surface: "watch",
    pairedDeviceId: s.a.deviceId,
    deviceActions: [],
  });
  s.setStage("stage_device_action", {});
  const unsupported = await s.create(body);
  expect((await s.drain(unsupported.body.id)).errorCode).toBe(
    "DEVICE_ACTION_UNSUPPORTED",
  );
  await s.h.services.agent.putManifest(s.a.userId, {
    ...s.manifest,
    deviceId: watch,
    surface: "watch",
    pairedDeviceId: s.a.deviceId,
  });
  const r = await s.create(body),
    run = await s.drain(r.body.id),
    c = run.deviceChallenge!;
  await s.h.database
    .client`update agent_device_challenges set challenge=jsonb_set(challenge,'{expiresAt}',to_jsonb('2020-01-01T00:00:00.000Z'::text)) where id=${c.id}`;
  expect(
    (await s.h.services.agent.getV2(s.a.userId, run.id)).deviceChallenge
      ?.status,
  ).toBe("expired");
  await expect(
    s.h.services.agent.ackV2(s.a.userId, c.id, uuid(), {
      deviceId: watch,
      digest: c.digest,
      recordingId: c.scope.recordingId,
      claimToken: uuid(),
      status: "executed",
      localState: "paused",
      reason: null,
    }),
  ).rejects.toMatchObject({ code: "DEVICE_CHALLENGE_EXPIRED" });
});
