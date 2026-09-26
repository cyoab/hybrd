import { z } from "@hono/zod-openapi";
import { Day, Id, Instant, Revision, uniqueBy, Zone } from "../domain/schemas";

export const Experience = z.enum([
  "new",
  "beginner",
  "intermediate",
  "advanced",
]);
export const HeartRateZones = z
  .object({
    schemaVersion: z.literal(1),
    configuration: z.enum(["custom", "default", "system", "unknown"]),
    ranges: z
      .array(
        z
          .object({
            minBpm: z.number().min(0).max(300),
            maxBpm: z.number().positive().max(300).nullable(),
          })
          .strict(),
      )
      .length(5),
  })
  .strict()
  .refine(
    (v) =>
      v.ranges.every(
        (r, i, a) =>
          (r.maxBpm === null ? i === a.length - 1 : r.maxBpm > r.minBpm) &&
          (i === 0 || a[i - 1]?.maxBpm === r.minBpm),
      ),
    "Five ordered contiguous zones are required; only the top may be open-ended",
  )
  .openapi("ReviewedHeartRateZones");
export const RunningRecord = z
  .object({
    distanceM: z.number().positive().max(1000000),
    elapsedSeconds: z.number().int().positive().max(604800),
    performedOn: Day.nullable(),
    classification: z.enum(["athlete_reported", "observed_effort"]),
  })
  .strict();
export const StrengthRecord = z
  .object({
    exerciseId: Id,
    loadKg: z.number().min(0).max(1000),
    reps: z.number().int().min(1).max(100),
    performedOn: Day.nullable(),
    classification: z.literal("athlete_reported"),
  })
  .strict();
export const AthleteDetails = z
  .object({
    preferredName: z.string().trim().min(1).max(40).nullable(),
    heightUnit: z.enum(["cm", "ft_in"]),
    dateOfBirth: Day.nullable(),
    age: z
      .object({ years: z.number().int().min(1).max(120), asOf: Day })
      .strict()
      .nullable(),
    weightKg: z.number().min(20).max(400).nullable(),
    heightCm: z.number().min(80).max(250).nullable(),
    heartRateZones: HeartRateZones.nullable(),
    runningRecords: z.array(RunningRecord).max(30),
    strengthRecords: z.array(StrengthRecord).max(30),
  })
  .strict()
  .refine(
    (v) => !(v.dateOfBirth && v.age),
    "Supply actual DOB or age with as-of date, not both",
  )
  .openapi("AthleteDetails");
export const ImportField = z.enum([
  "preferredName",
  "dateOfBirth",
  "weightKg",
  "heightCm",
  "heartRateZones",
  "runningRecords",
  "strengthRecords",
  "weeklyDistanceM",
  "currentStrengthSessionsPerWeek",
]);
export const ImportObservation = z
  .object({
    measuredAt: Instant.nullable(),
    fetchedAt: Instant,
    window: z
      .object({ start: Instant, end: Instant, timezone: Zone })
      .strict()
      .refine((v) => Date.parse(v.start) < Date.parse(v.end))
      .nullable(),
    coverage: z.enum([
      "complete_returned_records",
      "partial",
      "unknown",
      "sampled_runs_within_period",
    ]),
    durationBasis: z.enum(["moving", "active", "elapsed"]).nullable(),
    calculationVersion: z.literal(1),
  })
  .strict();
const decision = {
  field: ImportField,
  decision: z.enum(["accept", "edit", "reject"]),
};
export const ImportDecision = z
  .discriminatedUnion("source", [
    z
      .object({
        ...decision,
        source: z.literal("strava"),
        previewId: Id,
        previewRevision: Revision,
      })
      .strict(),
    z
      .object({
        ...decision,
        source: z.literal("healthkit"),
        batchId: Id,
        sourceIds: z.array(z.string().min(1).max(200)).min(1).max(100),
        observation: ImportObservation,
      })
      .strict(),
  ])
  .openapi("OnboardingImportDecision");
export const Provenance = z
  .object({
    field: ImportField,
    source: z.enum(["strava", "healthkit"]),
    editedFromSource: z.boolean(),
    verification: z.enum(["server_preview", "client_reported"]),
    reference: z.string().max(200),
    sourceIds: z.array(z.string().max(200)).max(100),
    observation: ImportObservation,
    reviewedAt: Instant,
  })
  .strict();
export const AthleteDetailsInput = z
  .object({ schemaVersion: z.literal(1), details: AthleteDetails })
  .strict()
  .openapi("AthleteDetailsInput");
export const OnboardingPreferences = z
  .object({
    runningLevel: Experience,
    strengthLevel: Experience,
    desiredStrengthSessionsPerWeek: z.number().int().min(1).max(4),
    focusMuscleIds: z
      .array(Id)
      .max(10)
      .refine((v) => uniqueBy(v, (x) => x)),
    equipmentConfirmed: z.literal(true),
    readiness: z.enum(["ready", "returning", "adjusting"]),
  })
  .strict()
  .openapi("OnboardingTrainingPreferences");
