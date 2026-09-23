import type { StravaActivity } from "./provider";

export type HistoryActivity = Pick<
  StravaActivity,
  "id" | "start_date" | "distance" | "elapsed_time" | "moving_time"
> & { kind: "running" | "strength" | "other"; eligibleForBest: boolean };
export type Best = {
  name: string;
  distanceM: number;
  elapsedSeconds: number;
  activityId: string;
  performedAt: string;
};
export type HistoryState = {
  after: number;
  before: number;
  page: number;
  phase: "zones" | "pages" | "bests";
  activities: HistoryActivity[];
  zones: {
    custom: boolean;
    ranges: { minBpm: number; maxBpm: number | null }[];
  } | null;
  candidates: string[];
  detailIndex: number;
  bests: Best[];
  complete: boolean;
  zonesUnavailable: boolean;
};
export function newHistory(now = Date.now()): HistoryState {
  const before = Math.floor(now / 1000);
  return {
    after: before - 365 * 86400,
    before,
    page: 1,
    phase: "zones",
    activities: [],
    zones: null,
    candidates: [],
    detailIndex: 0,
    bests: [],
    complete: false,
    zonesUnavailable: false,
  };
}
export function summarizeActivity(activity: StravaActivity): HistoryActivity {
  const sport = activity.sport_type ?? activity.type;
  return {
    id: activity.id,
    start_date: activity.start_date,
    distance: activity.distance,
    elapsed_time: activity.elapsed_time,
    moving_time: activity.moving_time,
    kind: ["Run", "TrailRun", "VirtualRun"].includes(sport ?? "")
      ? "running"
      : sport === "WeightTraining"
        ? "strength"
        : "other",
    eligibleForBest: !activity.manual && !activity.flagged,
  };
}
// Strava has no public all-time running-PB endpoint. Inspect a bounded set of
// promising runs and label the returned best efforts as observations, not PRs.
export function bestCandidates(activities: HistoryActivity[]) {
  const ids = new Set<string>();
  for (const distance of [1000, 1609, 5000, 10000, 21097, 42195])
    for (const run of activities
      .filter(
        (a) =>
          a.kind === "running" &&
          a.eligibleForBest &&
          a.distance >= distance &&
          a.moving_time > 0,
      )
      .sort(
        (a, b) =>
          a.moving_time / a.distance - b.moving_time / b.distance ||
          a.id.localeCompare(b.id),
      )
      .slice(0, 3))
      ids.add(run.id);
  return [...ids];
}
export function historyPreview(state: HistoryState, now = Date.now()) {
  const running = state.activities.filter((a) => a.kind === "running"),
    strength = state.activities.filter((a) => a.kind === "strength");
  const summarize = (days: number) => {
    const rows = running.filter(
      (a) => Date.parse(a.start_date) >= (state.before - days * 86400) * 1000,
    );
    const distanceM = rows.reduce((n, a) => n + a.distance, 0),
      movingSeconds = rows.reduce((n, a) => n + a.moving_time, 0);
    const paceRows = rows.filter((a) => a.distance > 0 && a.moving_time > 0);
    const paceDistance = paceRows.reduce((n, a) => n + a.distance, 0);
    const paceTime = paceRows.reduce((n, a) => n + a.moving_time, 0);
    return {
      days,
      runs: rows.length,
      distanceM: Math.round(distanceM),
      elapsedSeconds: rows.reduce((n, a) => n + a.elapsed_time, 0),
      movingSeconds,
      averageMovingPaceSecondsPerKm:
        paceDistance > 0 ? Math.round((paceTime / paceDistance) * 1000) : null,
      averageWeeklyDistanceM: Math.round((distanceM * 7) / days),
      averageRunsPerWeek: Math.round(((rows.length * 7) / days) * 100) / 100,
    };
  };
  return {
    source: "strava" as const,
    generatedAt: new Date(now).toISOString(),
    expiresAt: new Date(now + 7 * 86400_000).toISOString(),
    periodStart: new Date(state.after * 1000).toISOString(),
    periodEnd: new Date(state.before * 1000).toISOString(),
    activityCount: state.activities.length,
    historyComplete: state.complete,
    heartRateZones: state.zones,
    running: [7, 28, 365].map(summarize),
    strengthSessions: strength.length,
    longestRunM: running.length
      ? Math.round(Math.max(...running.map((r) => r.distance)))
      : null,
    observedBestEfforts: state.bests,
    bestEffortCoverage: {
      scope: "sampled_runs_within_period" as const,
      inspectedRuns: state.detailIndex,
      totalRuns: running.length,
      allTimePersonalBests: false as const,
    },
    missing: [
      "strength_personal_bests",
      "goals",
      "availability",
      "equipment",
      ...(state.zonesUnavailable ? ["heart_rate_zones"] : []),
    ],
    requiresReview: true as const,
  };
}
