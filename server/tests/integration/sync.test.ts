import { afterAll, describe, expect, test } from "bun:test";
import {
  goal,
  harness,
  mutation,
  planned,
  preferences,
  profile,
  uuid,
} from "./helpers";

const h = harness();
afterAll(() => h.close());
describe("canonical sync and plan history", () => {
  test("retry ledger, mixed batches, revisions, tombstones, paging and acknowledgement", async () => {
    const a = await h.account(),
      id = uuid(),
      m = mutation("athlete_goal", goal, id);
    const first = await a.push(m);
    expect(first.results[0].status).toBe("applied");
    expect((await a.push(m)).results).toEqual(first.results);
    expect(
      (await a.push({ ...m, payload: { ...m.payload, goalType: "different" } }))
        .results[0].error.code,
    ).toBe("IDEMPOTENCY_KEY_REUSED");
    const batch = await a.push(
      mutation("athlete", profile, a.athleteId, "update", "1"),
      mutation(
        "athlete_goal",
        { ...goal, status: "paused" },
        id,
        "update",
        "99",
      ),
      mutation("training_preferences", preferences, a.athleteId),
    );
    expect(batch.results.map((r: { status: string }) => r.status)).toEqual([
      "applied",
      "conflict",
      "applied",
    ]);
    const race = await Promise.all([
      a.push(
        mutation(
          "athlete_goal",
          { ...goal, status: "paused" },
          id,
          "update",
          "1",
        ),
      ),
      a.push(
        mutation(
          "athlete_goal",
          { ...goal, status: "completed" },
          id,
          "update",
          "1",
        ),
      ),
    ]);
    expect(race.map((r) => r.results[0].status).sort()).toEqual([
      "applied",
      "conflict",
    ]);
    expect(
      (await a.push(mutation("athlete_goal", {}, id, "delete", "2"))).results[0]
        .status,
    ).toBe("applied");
    let cursor = "0",
      more = true;
    const changes = [];
    while (more) {
      const r = await a.send(
        `/v1/sync/pull?deviceId=${a.deviceId}&cursor=${cursor}&limit=2`,
      );
      expect(r.status).toBe(200);
      const b = await r.json();
      changes.push(...b.changes);
      cursor = b.nextCursor;
      more = b.hasMore;
    }
    expect(
      changes.some(
        (c) =>
          c.entityId === id && c.operation === "delete" && c.payload === null,
      ),
    ).toBe(true);
    expect(
      changes.find((c) => c.entityType === "athlete").payload.timezone,
    ).toBe(profile.timezone);
    expect(
      (await a.send("/v1/sync/ack", { deviceId: a.deviceId, cursor })).status,
    ).toBe(204);
    await a.send("/v1/sync/ack", { deviceId: a.deviceId, cursor: "0" });
    const [state] = await h.database
      .client`select last_pulled_sequence::text as cursor from device_sync_state where device_id=${a.deviceId}`;
    expect(state?.cursor).toBe(cursor);
    expect(
      (
        await a.send(
          `/v1/sync/pull?deviceId=${a.deviceId}&cursor=9223372036854775807`,
        )
      ).status,
    ).toBe(400);
  });
  test("cross-athlete mutation IDs, records, devices and references never leak data", async () => {
    const a = await h.account(),
      b = await h.account(),
      id = uuid(),
      m = mutation("athlete_goal", goal, id);
    await a.push(m);
    expect((await b.push(m)).results[0].error.code).toBe(
      "IDEMPOTENCY_KEY_REUSED",
    );
    expect(
      (await b.push(mutation("athlete_goal", goal, id, "update", "1")))
        .results[0].error.code,
    ).toBe("ENTITY_ID_UNAVAILABLE");
    expect((await b.send(`/v1/sync/pull?deviceId=${a.deviceId}`)).status).toBe(
      403,
    );
    expect(
      JSON.stringify(
        await (await b.send(`/v1/sync/pull?deviceId=${b.deviceId}`)).json(),
      ),
    ).not.toContain(id);
    await h.services.revokeDevice(a.userId, a.deviceId);
    expect((await a.send(`/v1/sync/pull?deviceId=${a.deviceId}`)).status).toBe(
      403,
    );
  });
  test("run and strength aggregates round-trip, with exact historical result references", async () => {
    const a = await h.account(),
      p = await planned(a),
      runId = uuid(),
      strengthId = uuid();
    const results = await a.push(
      mutation(
        "workout_result",
        {
          discipline: "running",
          plannedWorkoutId: p.run.id,
          logicalWorkoutId: p.run.logicalWorkoutId,
          trainingDate: "2026-10-02",
          timezone: "America/Monterrey",
          completionStatus: "completed",
          sourceType: "healthkit",
          run: {
            distanceM: 5000,
            durationS: 1800,
            segments: [
              {
                id: uuid(),
                prescriptionStepId: p.run.run.blocks[0]?.steps[0]?.id,
                segmentType: "steady",
                sequence: 0,
                durationS: 1800,
                distanceM: 5000,
                repeatIteration: 0, // Native execution identities use zero-based repeats.
              },
            ],
          },
        },
        runId,
      ),
      mutation(
        "workout_result",
        {
          discipline: "strength",
          plannedWorkoutId: p.strength.id,
          logicalWorkoutId: p.strength.logicalWorkoutId,
          trainingDate: "2026-10-03",
          timezone: "America/Monterrey",
          completionStatus: "completed",
          sourceType: "manual",
          exercises: [
            {
              id: uuid(),
              prescribedExerciseId: p.strength.strength.exercises[0]?.id,
              exerciseId: "10000000-0000-4000-8003-000000000000",
              sequence: 0,
              sets: [
                {
                  id: uuid(),
                  prescribedSetId:
                    p.strength.strength.exercises[0]?.sets[0]?.id,
                  setNumber: 1,
                  setKind: "working",
                  reps: 5,
                  loadKg: 62.5,
                  rpe: 8,
                  status: "completed",
                },
              ],
            },
          ],
        },
        strengthId,
      ),
    );
    expect(results.results.map((r: { status: string }) => r.status)).toEqual([
      "applied",
      "applied",
    ]);
    const pull = await (
      await a.send(`/v1/sync/pull?deviceId=${a.deviceId}`)
    ).json();
    const r = pull.changes.find(
      (c: { entityId: string }) => c.entityId === strengthId,
    ).payload;
    expect(r.exercises[0].sets[0].loadKg).toBe(62.5);
    expect(r.trainingDate).toBe("2026-10-03");
    const plan = pull.changes.find(
      (c: { entityId: string }) => c.entityId === p.planId,
    ).payload;
    expect(
      plan.workouts.find((w: { id: string }) => w.id === p.run.id).run.blocks[0]
        .steps[0].durationS,
    ).toBe(1800);
    const changed = structuredClone(p.plan);
    for (const w of changed.workouts) {
      w.id = uuid();
      if ("run" in w)
        for (const b of w.run.blocks) {
          b.id = uuid();
          for (const s of b.steps) s.id = uuid();
        }
      if ("strength" in w)
        for (const e of w.strength.exercises) {
          e.id = uuid();
          for (const s of e.sets) s.id = uuid();
        }
    }
    const firstWorkout = changed.workouts[0];
    if (!firstWorkout) throw new Error("Missing fixture workout");
    firstWorkout.scheduledDate = "2026-10-05";
    const newId = uuid();
    expect(
      (
        await a.push(
          mutation(
            "plan_version",
            { ...changed, basePlanVersionId: p.planId, origin: "manual_edit" },
            newId,
          ),
        )
      ).results[0].status,
    ).toBe("applied");
    expect(
      (await a.push(p.activate(newId, p.planId))).results[0].error.code,
    ).toBe("COMPLETED_WORKOUT_IMMUTABLE");
    expect(
      (await a.push(mutation("plan_version", p.plan, p.planId, "update", "2")))
        .results[0].error.code,
    ).toBe("IMMUTABLE_RECORD");
    const source = {
      provider: "healthkit",
      externalId: "source-1",
      fingerprint: "fingerprint-1",
      workoutResultId: runId,
      importStatus: "imported",
      matchStatus: "confirmed",
      matchedLogicalWorkoutId: p.run.logicalWorkoutId,
    };
    expect(
      (await a.push(mutation("activity_source_record", source))).results[0]
        .status,
    ).toBe("applied");
    expect(
      (await a.push(mutation("activity_source_record", source))).results[0]
        .error.code,
    ).toBe("DUPLICATE_SOURCE");
    expect((await a.send("/v1/account", undefined, "DELETE")).status).toBe(204);
    expect((await a.send("/v1/bootstrap")).status).toBe(401);
    const [count] = await h.database
      .client`select count(*)::int as n from workout_results where athlete_id=${a.athleteId}`;
    expect(count?.n).toBe(0);
  });
  test("competing plan heads accept one version and atomic child failures leave no partial aggregate", async () => {
    const a = await h.account(),
      p = await planned(a);
    const versions = [];
    for (let i = 0; i < 2; i++) {
      const clone = structuredClone(p.run);
      clone.id = uuid();
      for (const block of clone.run.blocks) block.id = uuid();
      for (const block of clone.run.blocks)
        for (const step of block.steps) step.id = uuid();
      clone.scheduledDate = `2026-10-0${4 + i}`;
      const id = uuid();
      versions.push(id);
      expect(
        (
          await a.push(
            mutation(
              "plan_version",
              {
                ...p.plan,
                basePlanVersionId: p.planId,
                origin: "manual_edit",
                workouts: [clone],
              },
              id,
            ),
          )
        ).results[0].status,
      ).toBe("applied");
    }
    const outcomes = await Promise.all(
      versions.map((id) => a.push(p.activate(id, p.planId))),
    );
    expect(outcomes.map((o) => o.results[0].status).sort()).toEqual([
      "applied",
      "conflict",
    ]);
    const id = uuid(),
      bad = await a.push(
        mutation(
          "workout_result",
          {
            discipline: "strength",
            trainingDate: "2026-10-05",
            timezone: "UTC",
            completionStatus: "completed",
            sourceType: "manual",
            exercises: [
              { id: uuid(), exerciseId: uuid(), sequence: 0, sets: [] },
            ],
          },
          id,
        ),
      );
    expect(bad.results[0].status).toBe("rejected");
    const rows = await h.database
      .client`select id from workout_results where id=${id}`;
    expect(rows).toHaveLength(0);
  });
});

test("profile, baseline, availability, catalog preferences and context restore on a second installation", async () => {
  const a = await h.account(),
    baselineId = uuid(),
    dayId = uuid();
  const batch = await a.push(
    mutation(
      "baseline_snapshot",
      {
        periodStart: "2026-09-01",
        periodEnd: "2026-09-21",
        schemaVersion: 1,
        metrics: { weeklyDistanceM: 20000 },
        confidence: { running: 0.8 },
        source: "mixed",
      },
      baselineId,
    ),
    mutation(
      "availability_rule",
      {
        dayOfWeek: 1,
        available: true,
        maxSessions: 2,
        preference: "preferred",
      },
      dayId,
    ),
    mutation("availability_override", {
      date: "2026-10-10",
      available: false,
      maxSessions: 0,
      reason: "Travel",
    }),
    mutation("athlete_equipment", {
      equipmentId: "10000000-0000-4000-8001-000000000000",
      available: true,
    }),
    mutation("exercise_preference", {
      exerciseId: "10000000-0000-4000-8003-000000000000",
      preference: "preferred",
    }),
  );
  expect(batch.results.map((r: { status: string }) => r.status)).toEqual(
    Array(5).fill("applied"),
  );
  const second = uuid();
  await h.services.registerDevice(a.userId, second, {
    appVersion: "1",
    pushEnabled: false,
    pushEnvironment: "sandbox",
  });
  const restored = await (
    await a.send(`/v1/sync/pull?deviceId=${second}`)
  ).json();
  expect(
    restored.changes.find(
      (c: { entityId: string }) => c.entityId === baselineId,
    ).payload.periodStart,
  ).toBe("2026-09-01");
  expect(
    (await a.push(mutation("baseline_snapshot", {}, baselineId, "delete", "1")))
      .results[0].error.code,
  ).toBe("IMMUTABLE_RECORD");
  const deleted = await a.push(
    mutation("availability_rule", {}, dayId, "delete", "1"),
  );
  expect(deleted.results[0].status).toBe("applied");
  expect(
    (
      await a.push(
        mutation(
          "availability_rule",
          {
            dayOfWeek: 1,
            available: true,
            maxSessions: 1,
            preference: "neutral",
          },
          dayId,
          "update",
          "2",
        ),
      )
    ).results[0].status,
  ).toBe("applied");
  const catalog = await (await a.send("/v1/catalog")).json();
  expect(catalog.exercises.length).toBeGreaterThan(20);
  const exported = await (await a.send("/v1/account/export")).json();
  expect(exported.data.baseline_snapshot).toHaveLength(1);
  expect(JSON.stringify(exported)).not.toContain("authUserId");
  expect(JSON.stringify(exported)).not.toContain(a.headers.authorization);
});

test("cross-athlete context and workout prescription references are rejected atomically", async () => {
  const a = await h.account(),
    b = await h.account(),
    p = await planned(a),
    block = uuid();
  await b.push(
    mutation(
      "training_block",
      {
        name: "Other",
        startDate: "2026-10-01",
        endDate: "2026-10-31",
        phase: "build",
        status: "draft",
      },
      block,
    ),
  );
  const id = uuid();
  const create = await b.push(
    mutation("plan_version", { ...p.plan, trainingBlockId: block }, id),
  );
  expect(create.results[0].error.code).toBe("REFERENCE_UNAVAILABLE");
  const resultId = uuid(),
    result = {
      discipline: "running",
      plannedWorkoutId: p.run.id,
      logicalWorkoutId: p.run.logicalWorkoutId,
      trainingDate: "2026-10-02",
      timezone: "UTC",
      completionStatus: "completed",
      sourceType: "manual",
      run: { distanceM: 1000, durationS: 600 },
    };
  expect(
    (await b.push(mutation("workout_result", result, resultId))).results[0]
      .status,
  ).toBe("rejected");
  const rows = await h.database
    .client`select id from workout_results where id=${resultId}`;
  expect(rows).toHaveLength(0);
});

test("account deletion requires a fresh session", async () => {
  const a = await h.account();
  await h.database
    .client`update auth_session set created_at=now()-interval '20 minutes' where user_id=${a.userId}`;
  const response = await a.send("/v1/account", undefined, "DELETE");
  expect(response.status).toBe(403);
  expect((await response.json()).error.code).toBe("REAUTHENTICATION_REQUIRED");
  expect((await a.send("/v1/bootstrap")).status).toBe(200);
});
