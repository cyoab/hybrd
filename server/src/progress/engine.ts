import { hash } from "../db/store";
import { addDays } from "./calendar";
import {
  type Activity,
  type Comparison,
  type Group,
  type Milestone,
  type Point,
  type ProgressDay,
  RunType,
  type Totals,
} from "./schemas";

export type SetGroup = {
  exerciseId: string;
  exerciseName: string;
  reps: number;
  loadConvention: string;
  count: number;
  loadKg: number;
};
export type Actual = {
  canonicalSequence?: string;
  id: string;
  revision: string;
  logicalId: string | null;
  updatedAt: string;
  trainingDate: string;
  timezone: string;
  dateBasis: "performedDate" | "loggedDate";
  loggedAt: string | null;
  startedAt: string | null;
  endedAt: string | null;
  discipline: "running" | "strength";
  completionStatus: string;
  sourceType: string;
  title: string | null;
  runType: string | null;
  distanceM: number | null;
  runDurationS: number | null;
  durationS: number | null;
  sets: SetGroup[];
  excludedSets: number;
  nextSetAt: string | null;
  sources: number;
  unresolvedSources: number;
  deletedSources: number;
};
export type StoredPoint = Point & { order: string };
export type StoredGroup = { key: string; group: Group; points: StoredPoint[] };
export type StoredActivity = Activity & { order: string };
export type Projection = {
  activities: StoredActivity[];
  days: ProgressDay[];
  groups: StoredGroup[];
  metadata: { milestones: Milestone[]; exclusions: Record<string, number> };
  refreshAfter: string | null;
};
export const emptyTotals = (): Totals => ({
  runMeters: 0,
  strengthSets: 0,
  activeSeconds: 0,
  sessions: 0,
  runSessions: 0,
  liftSessions: 0,
  activeDays: 0,
});
export const percent = (current: number, previous: number) =>
  previous === 0 ? null : ((current - previous) / previous) * 100;
export function sum(days: Totals[]): Totals {
  const totals = emptyTotals();
  for (const day of days)
    for (const key of Object.keys(totals) as (keyof Totals)[])
      totals[key] += day[key];
  return totals;
}
export function series(
  days: ProgressDay[],
  end: string,
  count: number,
): ProgressDay[] {
  const byDate = new Map(days.map((d) => [d.date, d]));
  return Array.from({ length: count }, (_, i) => {
    const date = addDays(end, i - count + 1);
    return byDate.get(date) ?? { date, ...emptyTotals() };
  });
}
const compareText = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
const canonicalOrder = (a: Actual) =>
  `${(a.canonicalSequence ?? "0").padStart(19, "0")}|${a.updatedAt}|${a.revision.padStart(19, "0")}|${a.id}`;
export const pointOrder = (p: Point) =>
  `${p.trainingDate}|${p.occurredAt ?? ""}|${p.resultId}`;
const occurredAt = (a: Actual) =>
  a.dateBasis === "loggedDate" ? a.loggedAt : a.endedAt;
const definitions = [
  {
    key: "firstDay",
    requirement: "Train on your first day",
    target: 1,
    unit: "days",
  },
  {
    key: "bothDisciplines",
    requirement: "Log running and strength",
    target: 2,
    unit: "disciplines",
  },
  {
    key: "tenKilometers",
    requirement: "Run 10 kilometers",
    target: 10000,
    unit: "meters",
  },
  {
    key: "twentyFiveSets",
    requirement: "Complete 25 strength sets",
    target: 25,
    unit: "sets",
  },
  {
    key: "tenDays",
    requirement: "Train on 10 distinct days",
    target: 10,
    unit: "days",
  },
  {
    key: "fiftyKilometers",
    requirement: "Run 50 kilometers",
    target: 50000,
    unit: "meters",
  },
  {
    key: "hundredSets",
    requirement: "Complete 100 strength sets",
    target: 100,
    unit: "sets",
  },
  {
    key: "fiftyDays",
    requirement: "Train on 50 distinct days",
    target: 50,
    unit: "days",
  },
] as const;
export function milestoneValue(unit: Milestone["unit"], totals: Totals) {
  return unit === "days"
    ? totals.activeDays
    : unit === "meters"
      ? totals.runMeters
      : unit === "sets"
        ? totals.strengthSets
        : Number(totals.runSessions > 0) + Number(totals.liftSessions > 0);
}

// Inputs contain at most one preaggregated run, source summary and set group per result/group.
export function project(
  actuals: Actual[],
  athleteId: string,
  now: Date,
): Projection {
  const exclusions = {
    supersededResults: 0,
    skippedResults: 0,
    invalidResults: 0,
    futureInstantResults: 0,
    excludedSets: 0,
    unresolvedSources: 0,
  };
  const unique = new Map<string, Actual>();
  for (const a of actuals) {
    const prior = unique.get(a.id);
    if (!prior || canonicalOrder(a) > canonicalOrder(prior))
      unique.set(a.id, a);
  }
  const heads = new Map<string, Actual>();
  for (const a of unique.values()) {
    const key = a.logicalId ? `logical:${a.logicalId}` : `result:${a.id}`,
      prior = heads.get(key);
    if (!prior || canonicalOrder(a) > canonicalOrder(prior)) heads.set(key, a);
  }
  exclusions.supersededResults = unique.size - heads.size;
  const activities: StoredActivity[] = [],
    groups = new Map<string, StoredGroup>();
  let refreshAfter: string | null = null;
  const future = (instant: string | null) => {
    if (!instant || Date.parse(instant) <= now.getTime()) return false;
    if (!refreshAfter || instant < refreshAfter) refreshAfter = instant;
    return true;
  };
  for (const a of heads.values()) {
    // Evaluate all instants so a closer timestamp is never lost to short-circuiting.
    const futureInstants = [a.startedAt, a.endedAt, a.loggedAt].map(future);
    future(a.nextSetAt);
    if (futureInstants.some(Boolean)) {
      exclusions.futureInstantResults++;
      continue;
    }
    if (a.completionStatus === "skipped") {
      exclusions.skippedResults++;
      continue;
    }
    const running = a.discipline === "running";
    const sets = a.sets.filter(
      (s) =>
        s.exerciseId &&
        s.exerciseName.trim() &&
        Number.isInteger(s.reps) &&
        s.reps >= 1 &&
        s.reps <= 100 &&
        Number.isFinite(s.loadKg) &&
        s.loadKg >= 0 &&
        s.loadKg <= 1000 &&
        s.count > 0,
    );
    const setCount = sets.reduce((n, s) => n + s.count, 0);
    if (
      running
        ? !(
            Number.isFinite(a.distanceM) &&
            Number(a.distanceM) > 0 &&
            Number.isFinite(a.runDurationS) &&
            Number(a.runDurationS) > 0
          )
        : setCount === 0
    ) {
      exclusions.invalidResults++;
      continue;
    }
    const inferredDuration =
      a.startedAt && a.endedAt
        ? Math.max(0, (Date.parse(a.endedAt) - Date.parse(a.startedAt)) / 1000)
        : null;
    const duration = running
      ? a.runDurationS
      : (a.durationS ?? inferredDuration);
    const runType = RunType.safeParse(a.runType);
    const flags: string[] = [];
    if (duration === null) flags.push("missing_duration");
    if (a.dateBasis === "loggedDate") flags.push("legacy_logged_date");
    if (a.unresolvedSources) flags.push("unresolved_source_match");
    if (a.excludedSets) flags.push("excluded_sets");
    if (a.sets.some((s) => s.loadConvention === "assistance"))
      flags.push("assisted_sets_not_compared");
    if (running && !runType.success) flags.push("unknown_run_type_as_custom");
    if (running && a.completionStatus !== "completed")
      flags.push("incomplete_run_not_compared");
    if (running && Number(a.distanceM) < 1000)
      flags.push("short_run_not_compared");
    const activity: StoredActivity = {
      resultId: a.id,
      revision: a.revision,
      trainingDate: a.trainingDate,
      timezone: a.timezone,
      dateBasis: a.dateBasis,
      discipline: a.discipline,
      completionStatus: a.completionStatus,
      title: a.title ?? (running ? "Run" : "Strength"),
      loggedAt: a.loggedAt,
      completedAt: a.endedAt,
      runMeters: running ? Number(a.distanceM) : 0,
      strengthSets: running ? 0 : setCount,
      activeSeconds: Math.max(0, duration ?? 0),
      source: {
        type: a.sourceType,
        records: a.sources,
        unresolvedMatches: a.unresolvedSources,
        deletedRecords: a.deletedSources,
      },
      flags,
      order: canonicalOrder(a),
    };
    exclusions.excludedSets += a.excludedSets;
    exclusions.unresolvedSources += a.unresolvedSources;
    activities.push(activity);
    const add = (group: Group, value: number) => {
      // Identity never depends on display names or arbitrary prescription titles.
      const identity =
        group.kind === "running"
          ? group
          : {
              kind: group.kind,
              exerciseId: group.exerciseId,
              reps: group.reps,
              loadConvention: group.loadConvention,
            };
      const key = hash({ athleteId, rulesVersion: 1, group: identity });
      const stored = groups.get(key) ?? { key, group, points: [] };
      stored.points.push({
        resultId: a.id,
        trainingDate: a.trainingDate,
        occurredAt: occurredAt(a),
        value,
        order: canonicalOrder(a),
      });
      groups.set(key, stored);
    };
    if (
      running &&
      a.completionStatus === "completed" &&
      Number(a.distanceM) >= 1000
    )
      add(
        {
          kind: "running",
          distanceM: Number(a.distanceM),
          runType: runType.success ? runType.data : "custom",
        },
        Number(a.runDurationS) / (Number(a.distanceM) / 1000),
      );
    if (!running) {
      const heaviest = new Map<string, SetGroup>();
      for (const set of sets) {
        if (
          set.loadConvention !== "external" &&
          set.loadConvention !== "bodyweight"
        )
          continue;
        const key = `${set.exerciseId}:${set.reps}:${set.loadConvention}`,
          prior = heaviest.get(key);
        if (!prior || set.loadKg > prior.loadKg) heaviest.set(key, set);
      }
      for (const set of heaviest.values())
        add(
          {
            kind: "strength",
            exerciseId: set.exerciseId,
            exerciseName: set.exerciseName,
            reps: set.reps,
            loadConvention: set.loadConvention as "external" | "bodyweight",
          },
          set.loadKg,
        );
    }
  }
  activities.sort((a, b) =>
    compareText(
      pointOrder({
        resultId: a.resultId,
        trainingDate: a.trainingDate,
        occurredAt: a.dateBasis === "loggedDate" ? a.loggedAt : a.completedAt,
        value: 0,
      }),
      pointOrder({
        resultId: b.resultId,
        trainingDate: b.trainingDate,
        occurredAt: b.dateBasis === "loggedDate" ? b.loggedAt : b.completedAt,
        value: 0,
      }),
    ),
  );
  const byDay = new Map<string, ProgressDay>(),
    totals = emptyTotals();
  const milestones: Milestone[] = definitions.map((d) => ({
    ...d,
    rulesVersion: 1,
    current: 0,
    earnedAt: null,
    earnedOn: null,
    evidenceResultId: null,
  }));
  for (const a of activities) {
    const prior = byDay.get(a.trainingDate),
      day = prior ?? { date: a.trainingDate, ...emptyTotals(), activeDays: 1 };
    const increment: Totals = {
      runMeters: a.runMeters,
      strengthSets: a.strengthSets,
      activeSeconds: a.activeSeconds,
      sessions: 1,
      runSessions: Number(a.discipline === "running"),
      liftSessions: Number(a.discipline === "strength"),
      activeDays: 0,
    };
    for (const key of Object.keys(totals) as (keyof Totals)[]) {
      day[key] += increment[key];
      totals[key] += increment[key];
    }
    if (!prior) totals.activeDays++;
    byDay.set(a.trainingDate, day);
    for (const m of milestones)
      if (!m.earnedOn && milestoneValue(m.unit, totals) >= m.target) {
        m.earnedOn = a.trainingDate;
        m.earnedAt = a.dateBasis === "loggedDate" ? a.loggedAt : a.completedAt;
        m.evidenceResultId = a.resultId;
      }
  }
  for (const group of groups.values())
    group.points.sort((a, b) => compareText(pointOrder(a), pointOrder(b)));
  return {
    activities,
    days: [...byDay.values()],
    groups: [...groups.values()],
    metadata: { milestones, exclusions },
    refreshAfter,
  };
}

// Preserve endpoints and the exact best, then sample across the remaining history.
export function chart(
  points: StoredPoint[],
  best: StoredPoint,
  cap = 32,
): Point[] {
  if (points.length <= cap) return points;
  const indices = new Set([0, points.length - 1, points.indexOf(best)]);
  for (let i = 1; i < cap - 1 && indices.size < cap; i++)
    indices.add(Math.round((i * (points.length - 1)) / (cap - 1)));
  for (let i = 1; indices.size < cap; i++) indices.add(i);
  return [...indices]
    .sort((a, b) => a - b)
    .map((i) => points[i] as StoredPoint);
}
export function comparison(
  stored: StoredGroup,
  today: string,
): (Comparison & { order: string }) | null {
  const points = stored.points.filter((p) => p.trainingDate <= today);
  const first = points[0],
    latest = points.at(-1);
  if (!first || !latest || first.trainingDate === latest.trainingDate)
    return null;
  const running = stored.group.kind === "running";
  const best = points.reduce(
    (best, p) =>
      (running ? p.value < best.value : p.value > best.value) ? p : best,
    first,
  );
  const absolute = latest.value - first.value,
    steady = Math.abs(absolute) <= (running ? 0.5 : 0.01);
  const sampled = chart(points, best);
  return {
    key: stored.key,
    group: stored.group,
    unit: running ? "secondsPerKilometer" : "kilograms",
    first,
    latest,
    best,
    sampleCount: points.length,
    chartPoints: sampled,
    hasMore: points.length > sampled.length,
    change: {
      absolute,
      percent: percent(latest.value, first.value),
      direction: steady
        ? "steady"
        : (running ? absolute < 0 : absolute > 0)
          ? "improved"
          : "regressed",
    },
    order: points.reduce((last, p) => (last > p.order ? last : p.order), ""),
  };
}
