import type { z } from "zod";
import { ApiError } from "../api/errors";
import {
  HeartRateZones,
  type ImportDecision,
  type Provenance,
} from "../athlete/details";
import { hash, type Tx } from "../db/store";
import { OnboardingPreviewSchema } from "../strava/schemas";
import type { DraftData } from "./schemas";

type Decision = z.infer<typeof ImportDecision>;
type Field = Decision["field"];
export function getField(draft: DraftData, field: Field): unknown {
  return field === "weeklyDistanceM" ||
    field === "currentStrengthSessionsPerWeek"
    ? draft[field]
    : draft.details[field];
}
function setField(draft: DraftData, field: Field, value: unknown) {
  const target =
    field === "weeklyDistanceM" || field === "currentStrengthSessionsPerWeek"
      ? draft
      : draft.details;
  (target as Record<string, unknown>)[field] = value;
}
export function referenceOnlyDraft(draft: DraftData) {
  const copy = structuredClone(draft);
  for (const d of copy.importDecisions)
    if (d.source === "strava" && d.decision === "accept")
      setField(copy, d.field, d.field.endsWith("Records") ? [] : null);
  return copy;
}
function conflict(
  code: "IMPORT_PREVIEW_EXPIRED" | "IMPORT_REVIEW_REQUIRED",
  field: string,
): never {
  throw new ApiError(
    409,
    code,
    "Review this import again, or replace it with a manual answer.",
    { fields: [field] },
  );
}
export async function resolveImports(
  sql: Tx,
  owner: string,
  draft: DraftData,
  mode: "validate" | "hydrate",
  tolerateStale = false,
) {
  const result = structuredClone(draft),
    issues: {
      field: string;
      code: "IMPORT_PREVIEW_EXPIRED" | "IMPORT_REVIEW_REQUIRED";
    }[] = [],
    provenance: z.infer<typeof Provenance>[] = [];
  // The connection lock prevents a webhook/disconnect changing the reviewed version during completion.
  const [connection] = draft.importDecisions.some(
    (d) => d.source === "strava" && d.decision !== "reject",
  )
    ? await sql`select * from strava_connections where athlete_id=${owner} for update`
    : [];
  for (const d of draft.importDecisions) {
    if (d.decision === "reject") continue;
    const edited = d.decision === "edit",
      now = new Date().toISOString();
    try {
      if (d.source === "healthkit") {
        if (["preferredName", "strengthRecords"].includes(d.field))
          conflict("IMPORT_REVIEW_REQUIRED", d.field);
        if (getField(result, d.field) == null)
          conflict("IMPORT_REVIEW_REQUIRED", d.field);
        if (
          ["weeklyDistanceM", "currentStrengthSessionsPerWeek"].includes(
            d.field,
          )
        ) {
          const w = d.observation.window;
          if (!w || Date.parse(w.end) - Date.parse(w.start) !== 28 * 86400_000)
            conflict("IMPORT_REVIEW_REQUIRED", d.field);
        }
        if (
          Date.parse(d.observation.fetchedAt) > Date.now() + 300_000 ||
          (d.observation.measuredAt &&
            Date.parse(d.observation.measuredAt) >
              Date.parse(d.observation.fetchedAt)) ||
          (d.observation.window &&
            Date.parse(d.observation.window.end) >
              Date.parse(d.observation.fetchedAt))
        )
          conflict("IMPORT_REVIEW_REQUIRED", d.field);
        if (
          d.field === "runningRecords" &&
          !edited &&
          result.details.runningRecords.some(
            (r) => r.classification !== "observed_effort",
          )
        )
          conflict("IMPORT_REVIEW_REQUIRED", d.field);
        provenance.push({
          field: d.field,
          source: d.source,
          editedFromSource: edited,
          verification: "client_reported",
          reference: d.batchId,
          sourceIds: d.sourceIds,
          observation: d.observation,
          reviewedAt: now,
        });
        continue;
      }
      const parsed = OnboardingPreviewSchema.safeParse(
        connection?.onboarding_preview,
      );
      if (
        connection?.status !== "connected" ||
        !parsed.success ||
        !connection.history_expires_at ||
        new Date(connection.history_expires_at) <= new Date() ||
        Date.parse(parsed.data.expiresAt) <= Date.now()
      )
        conflict("IMPORT_PREVIEW_EXPIRED", d.field);
      const p = parsed.data;
      if (p.id !== d.previewId || p.revision !== d.previewRevision)
        conflict("IMPORT_REVIEW_REQUIRED", d.field);
      const section = ["preferredName", "weightKg"].includes(d.field)
        ? p.profile
        : d.field === "heartRateZones"
          ? p.heartRateZones
          : p.runningHistory;
      if (section.state !== "ready")
        conflict("IMPORT_REVIEW_REQUIRED", d.field);
      const h = p.runningHistory.data;
      const recent = h?.running.find((w) => w.days === 28);
      let value: unknown = null;
      switch (d.field) {
        case "preferredName":
          value = p.profile.data?.preferredName;
          break;
        case "weightKg":
          value = p.profile.data?.weightKg;
          break;
        case "heartRateZones":
          value = p.heartRateZones.data && {
            schemaVersion: 1,
            configuration: p.heartRateZones.data.custom ? "custom" : "default",
            ranges: p.heartRateZones.data.ranges,
          };
          break;
        case "weeklyDistanceM":
          value = recent?.averageWeeklyDistanceM;
          break;
        case "currentStrengthSessionsPerWeek":
          value = h?.strengthWindows?.find(
            (w) => w.days === 28,
          )?.averageSessionsPerWeek;
          break;
        case "runningRecords":
          value = h?.observedBestEfforts.map((e) => ({
            distanceM: e.distanceM,
            elapsedSeconds: e.elapsedSeconds,
            performedOn: e.performedAt.slice(0, 10),
            classification: "observed_effort",
          }));
          break;
        default:
          conflict("IMPORT_REVIEW_REQUIRED", d.field);
      }
      if (
        value == null ||
        (!edited &&
          d.field === "heartRateZones" &&
          !HeartRateZones.safeParse(value).success)
      )
        conflict("IMPORT_REVIEW_REQUIRED", d.field);
      if (
        !edited &&
        mode === "validate" &&
        hash(value) !== hash(getField(draft, d.field))
      )
        conflict("IMPORT_REVIEW_REQUIRED", d.field);
      if (!edited && mode === "hydrate") setField(result, d.field, value);
      if (edited && getField(draft, d.field) == null)
        conflict("IMPORT_REVIEW_REQUIRED", d.field);
      const historyField = [
        "weeklyDistanceM",
        "currentStrengthSessionsPerWeek",
        "runningRecords",
      ].includes(d.field);
      const recentField = [
        "weeklyDistanceM",
        "currentStrengthSessionsPerWeek",
      ].includes(d.field);
      provenance.push({
        field: d.field,
        source: "strava",
        editedFromSource: edited,
        verification: "server_preview",
        reference: `${p.id}:${p.revision}`,
        sourceIds:
          d.field === "runningRecords"
            ? (h?.observedBestEfforts.map((e) => e.activityId) ?? [])
            : [],
        reviewedAt: now,
        observation: {
          measuredAt: null,
          fetchedAt: section.fetchedAt ?? p.generatedAt,
          calculationVersion: 1,
          durationBasis:
            d.field === "runningRecords"
              ? "elapsed"
              : historyField
                ? "moving"
                : null,
          coverage:
            d.field === "runningRecords"
              ? "sampled_runs_within_period"
              : section.coverage,
          window:
            historyField && h
              ? {
                  start: recentField
                    ? new Date(
                        Date.parse(h.periodEnd) - 28 * 86400_000,
                      ).toISOString()
                    : h.periodStart,
                  end: h.periodEnd,
                  timezone: "UTC",
                }
              : null,
        },
      });
    } catch (e) {
      if (
        !tolerateStale ||
        !(e instanceof ApiError) ||
        !["IMPORT_PREVIEW_EXPIRED", "IMPORT_REVIEW_REQUIRED"].includes(e.code)
      )
        throw e;
      issues.push({
        field: d.field,
        code: e.code as "IMPORT_PREVIEW_EXPIRED" | "IMPORT_REVIEW_REQUIRED",
      });
    }
  }
  return { draft: result, provenance, issues };
}
