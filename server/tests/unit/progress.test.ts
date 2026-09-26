import { describe, expect, test } from "bun:test";
import { addDays, calendar } from "../../src/progress/calendar";
import { cursors } from "../../src/progress/cursor";
import {
  type Actual,
  comparison,
  percent,
  project,
  type SetGroup,
  series,
  sum,
} from "../../src/progress/engine";
import { ActivityQuery, SummaryQuery } from "../../src/progress/schemas";

const now = new Date("2026-03-10T16:00:00Z"),
  owner = crypto.randomUUID();
function run(offset = 0, overrides: Partial<Actual> = {}): Actual {
  const day = addDays("2026-03-10", offset),
    at = `${day}T12:00:00.000Z`;
  return {
    id: crypto.randomUUID(),
    revision: "1",
    logicalId: null,
    updatedAt: at,
    trainingDate: day,
    timezone: "America/New_York",
    dateBasis: "performedDate",
    loggedAt: at,
    startedAt: null,
    endedAt: at,
    discipline: "running",
    completionStatus: "completed",
    sourceType: "manual",
    title: null,
    runType: "easy",
    distanceM: 5000,
    runDurationS: 1800,
    durationS: null,
    sets: [],
    excludedSets: 0,
    nextSetAt: null,
    sources: 0,
    unresolvedSources: 0,
    deletedSources: 0,
    ...overrides,
  };
}
const set = (overrides: Partial<SetGroup> = {}): SetGroup => ({
  exerciseId: "10000000-0000-4000-8003-000000000000",
  exerciseName: "Back squat",
  reps: 5,
  loadConvention: "external",
  count: 3,
  loadKg: 50,
  ...overrides,
});
const lift = (offset = 0, overrides: Partial<Actual> = {}) =>
  run(offset, {
    discipline: "strength",
    completionStatus: "partial",
    distanceM: null,
    runDurationS: null,
    durationS: 600,
    sets: [set()],
    ...overrides,
  });
const snapshot = (items: Actual[]) => project(items, owner, now);
const views = (items: Actual[]) =>
  snapshot(items)
    .groups.map((g) => comparison(g, "2026-03-10"))
    .filter((c) => c !== null);

describe("progress rules v1 / native ProgressChecks migration fixtures", () => {
  test("canonical sequence resolves logical heads even when clocks tie or run backwards", () => {
    const logicalId = crypto.randomUUID();
    const old = run(-1, {
      logicalId,
      canonicalSequence: "9007199254740992",
      revision: "99",
    });
    const latest = run(-2, {
      logicalId,
      canonicalSequence: "9007199254740993",
      completionStatus: "skipped",
    });
    expect(snapshot([old, latest]).activities).toHaveLength(0);
    expect(snapshot([latest, old]).activities).toHaveLength(0);
  });
  test("empty, one-result and same-day doubles count actual days", () => {
    expect(
      snapshot([]).metadata.milestones.every((m) => m.earnedOn === null),
    ).toBe(true);
    const both = snapshot([run(), lift()]),
      totals = sum(both.days);
    expect(totals).toEqual({
      runMeters: 5000,
      strengthSets: 3,
      activeSeconds: 2400,
      sessions: 2,
      runSessions: 1,
      liftSessions: 1,
      activeDays: 1,
    });
    expect(
      both.metadata.milestones.find((m) => m.key === "bothDisciplines")
        ?.earnedOn,
    ).toBe("2026-03-10");
    expect(views([run()])).toHaveLength(0);
  });
  test("null logical IDs are distinct; corrected IDs and latest skipped logical heads suppress older actuals", () => {
    const a = run(-3),
      corrected = { ...a, revision: "2", distanceM: 2000 };
    expect(sum(snapshot([a, corrected]).days).runMeters).toBe(2000);
    expect(sum(snapshot([run(), run()]).days).sessions).toBe(2);
    const logicalId = crypto.randomUUID(),
      first = run(-3, { logicalId }),
      latest = run(-1, { logicalId, completionStatus: "skipped" });
    expect(snapshot([latest, first]).activities).toHaveLength(0);
    expect(
      snapshot([first, latest]).metadata.exclusions.supersededResults,
    ).toBe(1);
  });
  test("invalid, skipped and future instants are excluded; partial work and bodyweight count", () => {
    const p = snapshot([
      run(1),
      run(0, { distanceM: 0 }),
      run(0, { runDurationS: 0 }),
      run(0, { completionStatus: "skipped" }),
      lift(0, {
        sets: [
          set({ loadKg: 0 }),
          set({ reps: 0 }),
          set({ loadKg: Infinity }),
          set({ loadKg: -1 }),
          set({ exerciseName: " " }),
        ],
      }),
    ]);
    expect(sum(p.days).strengthSets).toBe(3);
    expect(sum(p.days).sessions).toBe(1);
    expect(p.refreshAfter).toBe("2026-03-11T12:00:00.000Z");
    expect(
      snapshot([run(0, { completionStatus: "partial" })]).activities,
    ).toHaveLength(1);
    expect(
      views([run(-1), run(0, { completionStatus: "partial" })]),
    ).toHaveLength(0);
  });
  test("rest preserves lifetime steps; corrected totals revoke threshold crossings", () => {
    const items = Array.from({ length: 10 }, (_, i) => run(i - 19));
    const p = snapshot(items);
    expect(sum(p.days).activeDays).toBe(10);
    expect(
      p.metadata.milestones.find((m) => m.key === "tenDays")?.earnedOn,
    ).toBe("2026-02-28");
    expect(
      p.metadata.milestones.find((m) => m.key === "tenKilometers")?.earnedOn,
    ).toBe("2026-02-20");
    expect(
      snapshot(items.slice(0, -1)).metadata.milestones.find(
        (m) => m.key === "fiftyKilometers",
      )?.earnedOn,
    ).toBeNull();
    expect(
      snapshot([
        lift(-2, { sets: [set({ count: 24 })] }),
        lift(-1, { sets: [set({ count: 1 })] }),
      ]).metadata.milestones.find((m) => m.key === "twentyFiveSets")?.earnedOn,
    ).toBe("2026-03-09");
  });
  test("7/28/84 days and previous windows zero-fill exactly across year, leap and DST", () => {
    const p = snapshot(
      Array.from({ length: 171 }, (_, i) =>
        run(-i, { distanceM: 1000, runDurationS: 360 }),
      ),
    );
    for (const count of [7, 28, 84]) {
      const current = series(p.days, "2026-03-10", count),
        previous = series(p.days, addDays("2026-03-10", -count), count);
      expect(current).toHaveLength(count);
      expect(sum(current).sessions).toBe(count);
      expect(sum(previous).runMeters).toBe(count * 1000);
      expect(new Set(current.map((d) => d.date)).size).toBe(count);
    }
    expect(series([], "2027-01-02", 7)[0]?.date).toBe("2026-12-27");
    expect(series([], "2024-03-01", 3).map((d) => d.date)).toEqual([
      "2024-02-28",
      "2024-02-29",
      "2024-03-01",
    ]);
    const ny = calendar("America/New_York");
    expect(
      ny.nextMidnight(new Date("2026-03-08T05:00:00Z")).toISOString(),
    ).toBe("2026-03-09T04:00:00.000Z");
    expect(
      ny.nextMidnight(new Date("2026-11-01T04:00:00Z")).toISOString(),
    ).toBe("2026-11-02T05:00:00.000Z");
    expect(ny.day(new Date("2026-03-10T03:59:59Z"))).toBe("2026-03-09");
    expect(ny.day(new Date("2026-03-10T04:00:00Z"))).toBe("2026-03-10");
  });
  test("run comparisons match exact meters/type, elapsed duration and distinct dates", () => {
    const faster = views([run(-5), run(0, { runDurationS: 1500 })])[0];
    expect(faster?.change.absolute).toBe(-60);
    expect(faster?.best.value).toBe(300);
    expect(faster?.change.direction).toBe("improved");
    for (const other of [
      run(0, { distanceM: 5001 }),
      run(0, { runType: "tempo" }),
      run(0, { completionStatus: "modified" }),
      run(0, { distanceM: 999 }),
    ])
      expect(views([run(-5), other])).toHaveLength(0);
    expect(views([run(), run(0, { runDurationS: 1500 })])).toHaveLength(0);
    expect(
      views([run(-1, { runType: "unknown" }), run(0, { runType: null })])[0]
        ?.group,
    ).toEqual({ kind: "running", runType: "custom", distanceM: 5000 });
  });
  test("canonical substitutions, reps and load conventions stay separate; heaviest set per session wins", () => {
    for (const other of [
      set({ reps: 8 }),
      set({ exerciseId: crypto.randomUUID() }),
      set({ loadConvention: "bodyweight" }),
      set({ loadConvention: "assistance" }),
    ])
      expect(views([lift(-5), lift(0, { sets: [other] })])).toHaveLength(0);
    const stronger = views([
      lift(-5),
      lift(-2, { sets: [set({ loadKg: 65 }), set({ loadKg: 55 })] }),
      lift(0, { sets: [set({ loadKg: 60, exerciseName: "Renamed squat" })] }),
    ])[0];
    expect(stronger?.sampleCount).toBe(3);
    expect(stronger?.best.value).toBe(65);
    expect(stronger?.change.absolute).toBe(10);
    expect(stronger?.change.direction).toBe("improved");
    expect(
      views([
        lift(-1, { sets: [set({ loadKg: 0 })] }),
        lift(0, { sets: [set({ loadKg: 0 })] }),
      ])[0]?.change.percent,
    ).toBeNull();
  });
  test("bounded charts retain exact extrema, endpoints, IDs and deterministic ordering", () => {
    const items = Array.from({ length: 171 }, (_, i) =>
      run(i - 170, { runDurationS: i === 83 ? 1000 : 2000 }),
    );
    const first = views(items)[0],
      reverse = views([...items].reverse())[0];
    expect(first).toEqual(reverse);
    expect(first?.chartPoints).toHaveLength(32);
    expect(first?.hasMore).toBe(true);
    expect(first?.best.resultId).toBe(items[83]?.id);
    expect(first?.chartPoints.some((p) => p.resultId === items[83]?.id)).toBe(
      true,
    );
    expect(first?.first.resultId).toBe(items[0]?.id);
    expect(first?.latest.resultId).toBe(items[170]?.id);
    expect(percent(1, 0)).toBeNull();
  });
  test("canonical migration preserves travel date and never invents legacy earnedAt", () => {
    const p = snapshot([
      run(0, {
        trainingDate: "2026-03-08",
        timezone: "Asia/Tokyo",
        endedAt: null,
        startedAt: null,
        loggedAt: null,
        dateBasis: "loggedDate",
      }),
    ]);
    expect(p.activities[0]?.trainingDate).toBe("2026-03-08");
    expect(p.metadata.milestones[0]?.earnedOn).toBe("2026-03-08");
    expect(p.metadata.milestones[0]?.earnedAt).toBeNull();
    expect(p.activities[0]?.flags).toContain("legacy_logged_date");
  });
  test("query contracts reject unsupported periods, historical asOf, zones, ranges and sizes", () => {
    for (const q of [
      { periodDays: 8 },
      { timezone: "bad/zone" },
      { timezone: "+02:00" },
      { asOf: "2026-01-01" },
    ])
      expect(SummaryQuery.safeParse(q).success).toBe(false);
    for (const q of [
      { from: "2026-02-30", to: "2026-03-01" },
      { from: "2026-03-02", to: "2026-03-01" },
      { from: "2020-01-01", to: "2026-01-01" },
      { from: "2026-01-01", to: "2026-01-02", limit: 101 },
    ])
      expect(ActivityQuery.safeParse(q).success).toBe(false);
  });
  test("cursor signatures bind owner/query, generation and expiration", () => {
    const codec = cursors("test-only-progress-secret"),
      generation = crypto.randomUUID();
    const value = codec.encode({
      scope: "owner:query",
      generation,
      expires: now.getTime() + 1,
      after: "date|id",
    });
    expect(codec.decode(value, "owner:query", generation, now)).toBe("date|id");
    expect(() =>
      codec.decode(`${value}a`, "owner:query", generation, now),
    ).toThrow("cursor");
    expect(() => codec.decode(value, "other:query", generation, now)).toThrow(
      "cursor",
    );
    expect(() =>
      codec.decode(value, "owner:query", crypto.randomUUID(), now),
    ).toThrow("Progress changed");
    expect(() =>
      codec.decode(
        value,
        "owner:query",
        generation,
        new Date(now.getTime() + 1),
      ),
    ).toThrow("Progress changed");
  });
});
