import { afterAll, describe, expect, test } from "bun:test";
import { withAthlete } from "../../src/db/store";
import { addDays } from "../../src/progress/calendar";
import { ensureProjection } from "../../src/progress/projection";
import { SummarySchema } from "../../src/progress/schemas";
import { harness, mutation, planned, uuid } from "./helpers";

let now = new Date("2026-10-31T16:00:00Z");
const h = harness({ progress: { now: () => now } });
afterAll(() => h.close());
const summaryPath =
  "/v1/progress/summary?periodDays=28&timezone=America/Monterrey";
const activityPath =
  "/v1/progress/activity?from=2026-10-01&to=2026-10-31&timezone=America/Monterrey&limit=1";
type Account = Awaited<ReturnType<typeof h.account>>;
const run = (date: string, overrides: Record<string, unknown> = {}) => ({
  discipline: "running",
  trainingDate: date,
  timezone: "America/Monterrey",
  completionStatus: "completed",
  sourceType: "manual",
  run: { distanceM: 5000, durationS: 1800, movingDurationS: 1400 },
  ...overrides,
});
const set = (number = 1, overrides: Record<string, unknown> = {}) => ({
  id: uuid(),
  setNumber: number,
  setKind: "working",
  reps: 5,
  loadKg: 50,
  status: "completed",
  ...overrides,
});
const lift = (
  date: string,
  sets = [set()],
  overrides: Record<string, unknown> = {},
) => ({
  discipline: "strength",
  trainingDate: date,
  timezone: "America/Monterrey",
  durationS: 600,
  completionStatus: "partial",
  sourceType: "manual",
  exercises: [
    {
      id: uuid(),
      exerciseId: "10000000-0000-4000-8003-000000000000",
      sequence: 0,
      sets,
    },
  ],
  ...overrides,
});
async function apply(a: Account, ...ms: ReturnType<typeof mutation>[]) {
  const response = await a.push(...ms);
  expect(response.results.map((r: { status: string }) => r.status)).toEqual(
    ms.map(() => "applied"),
  );
  return response;
}
async function summary(a: Account, path = summaryPath) {
  const response = await a.send(path);
  expect(response.status).toBe(200);
  return SummarySchema.parse(await response.json());
}

// All writes use real auth, sync validation, aggregate replacement and PostgreSQL transactions.
describe("progress endpoints and durable projections", () => {
  test("failed projection transactions retain the outbox; concurrent reads never mix revisions", async () => {
    const a = await h.account();
    const first = mutation("workout_result", run("2026-10-01"));
    await apply(a, first);
    const before = await summary(a);
    await apply(a, mutation("workout_result", run("2026-10-02")));
    await expect(
      withAthlete(h.database.client, a.userId, async (sql) => {
        await ensureProjection(sql, a.athleteId, now);
        throw new Error("Simulated crash before commit");
      }),
    ).rejects.toThrow("Simulated crash");
    const [state] = await h.database
      .client`select sequence::text from progress_state where athlete_id=${a.athleteId}`;
    expect(state?.sequence).toBe(before.dataRevision);
    expect(
      (
        await h.database
          .client`select * from progress_outbox where athlete_id=${a.athleteId}`
      ).length,
    ).toBe(1);
    const readers = Array.from({ length: 5 }, () => summary(a));
    const writer = apply(a, mutation("workout_result", run("2026-10-03")));
    const snapshots = await Promise.all(readers);
    await writer;
    for (const s of snapshots) {
      expect([2, 3]).toContain(s.totals.lifetime.sessions);
      expect(s.totals.lifetime.runMeters).toBe(
        s.totals.lifetime.sessions * 5000,
      );
      expect(s.dataRevision).toBe(s.projectionSequence);
      expect(
        s.milestones.find((m) => m.key === "tenKilometers")?.earnedOn,
      ).toBe("2026-10-02");
    }
    expect((await summary(a)).totals.lifetime.sessions).toBe(3);
  });
  test("assisted loads, missing duration and due set timestamps retain explicit provenance", async () => {
    const a = await h.account();
    await apply(
      a,
      mutation(
        "workout_result",
        lift("2026-10-01", [set(1, { loadConvention: "assistance" })], {
          durationS: null,
        }),
      ),
      mutation(
        "workout_result",
        lift("2026-10-02", [set(1, { loadConvention: "assistance" })], {
          durationS: null,
          startedAt: "2026-10-02T15:00:00Z",
          endedAt: "2026-10-02T15:20:00Z",
        }),
      ),
      mutation(
        "workout_result",
        lift("2026-10-31", [set(1, { completedAt: "2026-10-31T17:00:00Z" })]),
      ),
    );
    const before = await summary(a);
    expect(before.totals.lifetime.strengthSets).toBe(2);
    expect(before.totals.lifetime.activeSeconds).toBe(1200);
    expect(before.comparisons).toHaveLength(0);
    expect(
      before.recentActivity.find((a) => a.trainingDate === "2026-10-01")?.flags,
    ).toContain("missing_duration");
    expect(before.recentActivity[0]?.flags).toContain(
      "assisted_sets_not_compared",
    );
    now = new Date("2026-10-31T17:00:00Z");
    try {
      expect((await summary(a)).totals.lifetime.strengthSets).toBe(3);
    } finally {
      now = new Date("2026-10-31T16:00:00Z");
    }
  });
  test("empty summary, strict queries, zero denominators and authenticated conditional cache", async () => {
    const a = await h.account(),
      initial = await a.send(summaryPath),
      body = SummarySchema.parse(await initial.json());
    expect(initial.status).toBe(200);
    expect(body.series).toHaveLength(28);
    expect(body.activityDays).toHaveLength(28);
    expect(body.totals.current.sessions).toBe(0);
    expect(body.totals.percentChange.runMeters).toBeNull();
    expect(body.journey).toEqual({
      trainingDays: 0,
      level: 1,
      stepsInLevel: 0,
      stepsToNextLevel: 10,
    });
    expect(body.dataRevision).toBe(body.projectionSequence);
    const cached = await h.app.request(summaryPath, {
      headers: {
        ...a.headers,
        "if-none-match": `W/${initial.headers.get("etag")}`,
      },
    });
    expect(cached.status).toBe(304);
    expect(await cached.text()).toBe("");
    expect(cached.headers.get("cache-control")).toBe(
      "private, no-cache, must-revalidate",
    );
    expect(
      (
        await h.app.request(summaryPath, {
          headers: { "if-none-match": initial.headers.get("etag") ?? "" },
        })
      ).status,
    ).toBe(401);
    for (const path of [
      "/v1/progress/summary?periodDays=14",
      "/v1/progress/summary?timezone=invalid",
      "/v1/progress/summary?asOf=2026-01-01",
      "/v1/progress/summary?athleteId=other",
      `${activityPath}&limit=101`,
      "/v1/progress/activity?from=2026-02-30&to=2026-03-01",
      "/v1/progress/activity?from=2026-10-31&to=2026-10-01",
    ]) {
      const response = await a.send(path);
      expect(response.status).toBe(400);
      expect((await response.json()).error.requestId).toBe(
        response.headers.get("x-request-id"),
      );
    }
  });
  test("calendar windows, stable travel dates, partial today and legacy migration provenance", async () => {
    const a = await h.account(),
      ms = Array.from({ length: 171 }, (_, i) =>
        mutation(
          "workout_result",
          run(addDays("2026-10-31", -i), {
            run: { distanceM: 1000, durationS: 360 },
          }),
        ),
      );
    await apply(a, ...ms.slice(0, 100));
    await apply(a, ...ms.slice(100));
    for (const period of [7, 28, 84]) {
      const body = await summary(
        a,
        `/v1/progress/summary?periodDays=${period}&timezone=America/Monterrey`,
      );
      expect(body.totals.current.sessions).toBe(period);
      expect(body.totals.previous.sessions).toBe(period);
      expect(body.series.reduce((n, d) => n + d.runMeters, 0)).toBe(
        period * 1000,
      );
      expect(body.activityDays).toHaveLength(28);
      expect(body.totals.lifetime.activeDays).toBe(171);
      expect(body.range.includesPartialToday).toBe(true);
      expect(body.comparisons[0]?.sampleCount).toBe(171);
      expect(body.comparisons[0]?.chartPoints).toHaveLength(32);
    }
    await apply(
      a,
      mutation(
        "workout_result",
        run("2026-10-01", {
          dateBasis: "loggedDate",
          loggedAt: "2026-10-02T02:00:00Z",
          timezone: "America/Monterrey",
        }),
      ),
    );
    expect((await summary(a)).dateBasis).toBe("mixed");
    const history = await a.send(
      "/v1/progress/activity?from=2026-10-01&to=2026-10-01&timezone=Asia/Tokyo",
    );
    const legacy = (await history.json()).activity.find(
      (r: { dateBasis: string }) => r.dateBasis === "loggedDate",
    );
    expect(legacy.trainingDate).toBe("2026-10-01");
    expect(legacy.completedAt).toBeNull();
    expect(legacy.flags).toContain("legacy_logged_date");
  });
  test("transactional outbox, replay, corrections, old dates and revoked awards", async () => {
    const a = await h.account(),
      first = mutation("workout_result", run("2026-10-01")),
      second = mutation("workout_result", run("2026-10-02"));
    await summary(a);
    await apply(a, first, second);
    const [pending] = await h.database
      .client`select sequence::text from progress_outbox where athlete_id=${a.athleteId}`;
    const [old] = await h.database
      .client`select sequence::text from progress_state where athlete_id=${a.athleteId}`;
    expect(BigInt(String(pending?.sequence))).toBeGreaterThan(
      BigInt(String(old?.sequence)),
    );
    const before = await summary(a);
    expect(before.dataRevision).toBe(pending?.sequence);
    expect(
      before.milestones.find((m) => m.key === "tenKilometers")?.earnedOn,
    ).toBe("2026-10-02");
    expect(
      (
        await h.database
          .client`select * from progress_outbox where athlete_id=${a.athleteId}`
      ).length,
    ).toBe(0);
    await apply(a, second); // Mutation replay must not emit a new revision/job.
    expect((await summary(a)).dataRevision).toBe(before.dataRevision);
    await h.database
      .client`insert into progress_outbox (athlete_id,sequence) values (${a.athleteId},${before.dataRevision})`;
    expect((await summary(a)).asOf).toBe(before.asOf);
    expect(
      (
        await h.database
          .client`select * from progress_outbox where athlete_id=${a.athleteId}`
      ).length,
    ).toBe(0);
    await apply(
      a,
      mutation(
        "workout_result",
        run("2026-10-20", { run: { distanceM: 2000, durationS: 800 } }),
        second.entityId,
        "update",
        "1",
      ),
    );
    const corrected = await summary(a);
    expect(corrected.totals.lifetime.runMeters).toBe(7000);
    expect(
      corrected.milestones.find((m) => m.key === "tenKilometers")?.earnedOn,
    ).toBeNull();
    expect(
      (
        await h.database
          .client`select * from progress_days where athlete_id=${a.athleteId} and date='2026-10-02'`
      ).length,
    ).toBe(0);
    await apply(
      a,
      mutation("workout_result", {}, first.entityId, "delete", "1"),
    );
    expect(
      (await summary(a)).milestones.find((m) => m.key === "firstDay")?.earnedOn,
    ).toBe("2026-10-20");
  });
  test("source joins never multiply actuals; source deletion preserves the workout and matching refreshes provenance", async () => {
    const a = await h.account(),
      r = mutation("workout_result", run("2026-10-10"));
    await apply(a, r);
    const source = (status: string) => ({
      provider: "healthkit",
      externalId: uuid(),
      fingerprint: uuid(),
      workoutResultId: r.entityId,
      importStatus: "imported",
      matchStatus: status,
    });
    const s1 = mutation("activity_source_record", source("suggested")),
      s2 = mutation("activity_source_record", source("confirmed"));
    await apply(a, s1, s2);
    const initial = await summary(a);
    expect(initial.totals.lifetime.sessions).toBe(1);
    expect(initial.totals.lifetime.runMeters).toBe(5000);
    expect(initial.recentActivity[0]?.source.records).toBe(2);
    expect(initial.recentActivity[0]?.flags).toContain(
      "unresolved_source_match",
    );
    await apply(
      a,
      mutation(
        "activity_source_record",
        { ...(s1.payload as object), matchStatus: "confirmed" },
        s1.entityId,
        "update",
        "1",
      ),
    );
    expect((await summary(a)).recentActivity[0]?.source.unresolvedMatches).toBe(
      0,
    );
    await apply(
      a,
      mutation("activity_source_record", {}, s2.entityId, "delete", "1"),
    );
    const deleted = await summary(a);
    expect(deleted.totals.lifetime.runMeters).toBe(5000);
    expect(deleted.recentActivity[0]?.source.deletedRecords).toBe(1);
    const dupe = mutation("activity_source_record", s1.payload);
    expect((await a.push(dupe)).results[0].status).toBe("conflict");
    expect((await summary(a)).dataRevision).toBe(deleted.dataRevision);
  });
  test("strength sets include extras/bodyweight/warmups, exclude failed/skipped, and replace atomically", async () => {
    const a = await h.account();
    const first = mutation(
      "workout_result",
      lift(
        "2026-10-01",
        Array.from({ length: 24 }, (_, i) =>
          set(i, { loadKg: 0, setKind: "warmup" }),
        ),
      ),
    );
    const second = mutation(
      "workout_result",
      lift("2026-10-02", [
        set(1, { setKind: "backoff" }),
        set(2, { status: "failed" }),
        set(3, { status: "skipped" }),
        set(4, { reps: 0 }),
        set(5, { loadKg: 1001 }),
      ]),
    );
    await apply(a, first, second);
    const before = await summary(a);
    expect(before.totals.lifetime.strengthSets).toBe(25);
    expect(before.totals.lifetime.activeSeconds).toBe(1200);
    expect(
      before.milestones.find((m) => m.key === "twentyFiveSets")?.earnedOn,
    ).toBe("2026-10-02");
    expect(before.exclusions.excludedSets).toBe(4);
    expect(before.comparisons[0]?.change.percent).toBeNull();
    await apply(
      a,
      mutation(
        "workout_result",
        lift("2026-10-01", [set()]),
        first.entityId,
        "update",
        "1",
      ),
    );
    const after = await summary(a);
    expect(after.totals.lifetime.strengthSets).toBe(2);
    expect(
      after.milestones.find((m) => m.key === "twentyFiveSets")?.earnedOn,
    ).toBeNull();
    const invalid = lift("2026-10-03");
    invalid.exercises = invalid.exercises.map((e) => ({
      ...e,
      exerciseId: uuid(),
    }));
    const rejected = mutation("workout_result", invalid);
    expect((await a.push(rejected)).results[0].status).toBe("rejected");
    expect(
      (
        await h.database
          .client`select * from workout_results where id=${rejected.entityId}`
      ).length,
    ).toBe(0);
    expect((await summary(a)).dataRevision).toBe(after.dataRevision);
  });
  test("exact historical plan types, latest logical result eligibility and immutable prescriptions", async () => {
    const a = await h.account(),
      p = await planned(a);
    const link = {
      plannedWorkoutId: p.run.id,
      logicalWorkoutId: p.run.logicalWorkoutId,
    };
    const older = mutation("workout_result", run("2026-10-02", link)),
      latest = mutation("workout_result", run("2026-10-03", link));
    await apply(a, older, latest);
    expect((await summary(a)).totals.lifetime.sessions).toBe(1);
    await apply(
      a,
      mutation(
        "workout_result",
        run("2026-10-03", { ...link, completionStatus: "skipped", run: null }),
        latest.entityId,
        "update",
        "1",
      ),
    );
    expect((await summary(a)).totals.lifetime.sessions).toBe(0);
    const newRun = {
      ...p.run,
      id: uuid(),
      logicalWorkoutId: uuid(),
      scheduledDate: "2026-10-04",
      title: "Tempo title cannot change easy type",
      run: {
        ...p.run.run,
        blocks: p.run.run.blocks.map((b) => ({
          ...b,
          id: uuid(),
          steps: b.steps.map((s) => ({ ...s, id: uuid() })),
        })),
      },
    };
    const carriedRun = {
      ...p.run,
      id: uuid(),
      run: {
        ...p.run.run,
        blocks: p.run.run.blocks.map((b) => ({
          ...b,
          id: uuid(),
          steps: b.steps.map((s) => ({ ...s, id: uuid() })),
        })),
      },
    };
    const planId = uuid();
    await apply(
      a,
      mutation(
        "plan_version",
        {
          ...p.plan,
          basePlanVersionId: p.planId,
          origin: "manual_edit",
          workouts: [carriedRun, newRun],
        },
        planId,
      ),
    );
    await apply(a, p.activate(planId, p.planId));
    await apply(
      a,
      mutation(
        "workout_result",
        run("2026-10-03", link),
        latest.entityId,
        "update",
        "2",
      ),
      mutation(
        "workout_result",
        run("2026-10-04", {
          plannedWorkoutId: newRun.id,
          logicalWorkoutId: newRun.logicalWorkoutId,
          run: { distanceM: 5000, durationS: 1500, movingDurationS: 1200 },
        }),
      ),
    );
    const body = await summary(a);
    expect(body.comparisons[0]?.group).toEqual({
      kind: "running",
      runType: "easy",
      distanceM: 5000,
    });
    expect(body.comparisons[0]?.change.absolute).toBe(-60);
    expect(body.comparisons[0]?.first.value).toBe(360);
  });
  test("history is stable, bounded, owner scoped and expires after a concurrent correction", async () => {
    const a = await h.account(),
      b = await h.account();
    const ms = ["2026-10-01", "2026-10-02", "2026-10-02", "2026-10-03"].map(
      (date) => mutation("workout_result", run(date)),
    );
    await apply(a, ...ms);
    const s = await summary(a),
      key = s.comparisons[0]?.key;
    const path = `/v1/progress/comparisons/${key}?limit=2&timezone=America/Monterrey`;
    const first = await (await a.send(path)).json();
    expect(first.points).toHaveLength(2);
    const second = await (
      await a.send(`${path}&cursor=${encodeURIComponent(first.nextCursor)}`)
    ).json();
    expect(second.points).toHaveLength(2);
    expect(second.nextCursor).toBeNull();
    expect(
      new Set([...first.points, ...second.points].map((p) => p.resultId)).size,
    ).toBe(4);
    expect((await b.send(path)).status).toBe(404);
    expect(
      (await b.send(`${path}&cursor=${encodeURIComponent(first.nextCursor)}`))
        .status,
    ).toBe(400);
    const page = await (await a.send(activityPath)).json();
    expect(page.activity).toHaveLength(1);
    expect(page.activity[0].resultId).toBe(ms[3]?.entityId);
    expect(
      (
        await a.send(
          `${path.replace("limit=2", "limit=3")}&cursor=${encodeURIComponent(first.nextCursor)}`,
        )
      ).status,
    ).toBe(400);
    await apply(
      a,
      mutation(
        "workout_result",
        run("2026-10-03", { run: { distanceM: 5000, durationS: 1400 } }),
        ms[3]?.entityId,
        "update",
        "1",
      ),
    );
    for (const stale of [
      `${path}&cursor=${encodeURIComponent(first.nextCursor)}`,
      `${activityPath}&cursor=${encodeURIComponent(page.nextCursor)}`,
    ]) {
      const response = await a.send(stale);
      expect(response.status).toBe(409);
      expect((await response.json()).error.code).toBe(
        "PROGRESS_CURSOR_EXPIRED",
      );
    }
    const changed = await summary(a);
    expect(changed.comparisons[0]?.best.resultId).toBe(ms[3]?.entityId);
    await apply(
      a,
      mutation("workout_result", {}, ms[3]?.entityId, "delete", "2"),
    );
    expect((await summary(a)).comparisons[0]?.best.value).toBe(360);
  });
  test("future dates and timestamps become eligible; midnight changes ETag and expires pages", async () => {
    const a = await h.account();
    await apply(
      a,
      mutation("workout_result", run("2026-10-30")),
      mutation("workout_result", run("2026-10-31")),
      mutation(
        "workout_result",
        run("2026-10-31", { endedAt: "2026-10-31T17:00:00Z" }),
      ),
      mutation("workout_result", run("2026-11-01")),
    );
    const initial = await a.send(summaryPath),
      initialBody = await initial.json();
    expect(initialBody.totals.lifetime.sessions).toBe(2);
    expect(initialBody.exclusions.futureDateResults).toBe(1);
    const page = await (await a.send(activityPath)).json();
    now = new Date("2026-10-31T17:00:00Z");
    const due = await summary(a);
    expect(due.totals.lifetime.sessions).toBe(3);
    expect(due.dataRevision).toBe(initialBody.dataRevision); // Time invalidation still changes generation/ETag.
    expect(
      (
        await a.send(
          `${activityPath}&cursor=${encodeURIComponent(page.nextCursor)}`,
        )
      ).status,
    ).toBe(409);
    const beforeMidnight = await a.send(summaryPath),
      latestPage = await (await a.send(activityPath)).json();
    now = new Date("2026-11-01T06:00:00Z");
    const next = await h.app.request(summaryPath, {
      headers: {
        ...a.headers,
        "if-none-match": beforeMidnight.headers.get("etag") ?? "",
      },
    });
    expect(next.status).toBe(200);
    expect((await next.json()).totals.lifetime.sessions).toBe(4);
    expect(
      (
        await a.send(
          `${activityPath}&cursor=${encodeURIComponent(latestPage.nextCursor)}`,
        )
      ).status,
    ).toBe(409);
    now = new Date("2026-10-31T16:00:00Z");
  });
  test("deleting an account purges projections, outbox and private caches", async () => {
    const a = await h.account();
    await apply(
      a,
      mutation("workout_result", run("2026-10-01")),
      mutation("workout_result", run("2026-10-02")),
    );
    await summary(a);
    await apply(a, mutation("workout_result", run("2026-10-03")));
    for (const table of [
      "progress_state",
      "progress_days",
      "progress_activity",
      "progress_comparisons",
      "progress_cache",
      "progress_outbox",
    ])
      expect(
        (
          await h.database
            .client`select * from ${h.database.client(table)} where athlete_id=${a.athleteId}`
        ).length,
      ).toBeGreaterThan(0);
    expect((await a.send("/v1/account", undefined, "DELETE")).status).toBe(204);
    for (const table of [
      "progress_state",
      "progress_days",
      "progress_activity",
      "progress_comparisons",
      "progress_cache",
      "progress_outbox",
    ])
      expect(
        (
          await h.database
            .client`select * from ${h.database.client(table)} where athlete_id=${a.athleteId}`
        ).length,
      ).toBe(0);
    expect((await a.send(summaryPath)).status).toBe(401);
  });
});
