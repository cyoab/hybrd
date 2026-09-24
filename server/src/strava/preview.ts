import type { z } from "zod";
import { type HistoryState, historyPreview } from "./history";
import { OnboardingPreviewSchema } from "./schemas";
export function onboardingPreview(
  s: HistoryState,
  scopes: string[],
  now = Date.now(),
): z.infer<typeof OnboardingPreviewSchema> {
  const activity = scopes.some((x) =>
    ["activity:read", "activity:read_all"].includes(x),
  );
  const profile = scopes.some((x) => ["read", "profile:read_all"].includes(x));
  const time = new Date(now).toISOString();
  const make = (
    allowed: boolean,
    pending: boolean,
    data: unknown,
    failure: string | null,
    coverage = "unknown",
    fetchedAt: string | null = null,
  ) => ({
    state: !allowed
      ? "unavailable"
      : failure
        ? "failed"
        : pending
          ? "pending"
          : data
            ? "ready"
            : "unavailable",
    reason: !allowed
      ? "scope_missing"
      : failure
        ? failure === "STRAVA_SCOPE_REQUIRED"
          ? "scope_missing"
          : "provider_unavailable"
        : pending || data
          ? null
          : "not_provided",
    data,
    source: "strava",
    fetchedAt: pending ? null : (fetchedAt ?? time),
    retryAfterSeconds: null,
    coverage,
  });
  const history =
    activity && s.phase === "bests" && !s.historyFailure
      ? historyPreview(s, now)
      : null;
  const running = make(
    activity,
    s.phase !== "bests",
    history,
    s.historyFailure,
    s.complete && scopes.includes("activity:read_all")
      ? "complete_returned_records"
      : "partial",
  );
  if (history)
    running.reason =
      !s.complete || !scopes.includes("activity:read_all")
        ? "history_partial"
        : !history.activityCount
          ? "no_activities"
          : null;
  return OnboardingPreviewSchema.parse({
    id: s.previewId,
    revision: String(s.revision),
    generatedAt: time,
    expiresAt: new Date((s.before + 7 * 86400) * 1000).toISOString(),
    profile: make(
      profile,
      s.phase === "profile",
      s.profile &&
        (s.profile.preferredName !== null || s.profile.weightKg !== null)
        ? { ...s.profile, measuredAt: null }
        : null,
      s.profileFailure,
      "unknown",
      s.profileFetchedAt,
    ),
    heartRateZones: make(
      scopes.includes("profile:read_all"),
      ["profile", "zones"].includes(s.phase),
      s.zones,
      s.zonesFailure,
      "unknown",
      s.zonesFetchedAt,
    ),
    runningHistory: running,
  });
}
