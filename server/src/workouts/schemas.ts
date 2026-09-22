import { z } from "@hono/zod-openapi";
import {
  Count,
  Day,
  Distance,
  Effort,
  Id,
  Load,
  Notes,
  optionalId,
  optionalInstant,
  Seconds,
  uniqueBy,
  Zone,
} from "../domain/schemas";

const heart = z.number().int().min(20).max(250).nullable().default(null);
const segment = z
  .object({
    id: Id,
    prescriptionStepId: optionalId,
    segmentType: z.enum([
      "split",
      "warmup",
      "work",
      "recovery",
      "cooldown",
      "steady",
      "stride",
    ]),
    sequence: Count,
    repeatIteration: Count.nullable().default(null),
    distanceM: Distance.nullable().default(null),
    durationS: Seconds,
    avgHrBpm: heart,
    maxHrBpm: heart,
    elevationGainM: z.number().nonnegative().nullable().default(null),
    avgCadenceSpm: z.number().nonnegative().max(400).nullable().default(null),
    startOffsetS: Seconds.nullable().default(null),
  })
  .strict();
export const RunResultInput = z
  .object({
    distanceM: Distance,
    durationS: Seconds,
    movingDurationS: Seconds.nullable().default(null),
    avgHrBpm: heart,
    maxHrBpm: heart,
    elevationGainM: z.number().nonnegative().nullable().default(null),
    avgCadenceSpm: z.number().nonnegative().max(400).nullable().default(null),
    hrZoneSummary: z
      .array(
        z
          .object({
            minBpm: z.number().int().min(0).max(250),
            maxBpm: z.number().int().min(0).max(250),
            durationS: Seconds,
          })
          .strict()
          .refine((v) => v.minBpm <= v.maxBpm),
      )
      .max(10)
      .default([]),
    segments: z.array(segment).max(500).default([]),
  })
  .strict()
  .refine(
    (v) =>
      (v.movingDurationS == null || v.movingDurationS <= v.durationS) &&
      uniqueBy(v.segments, (s) => s.id) &&
      uniqueBy(v.segments, (s) => s.sequence),
    "Invalid run durations or duplicate segments",
  );
const set = z
  .object({
    id: Id,
    prescribedSetId: optionalId,
    setNumber: Count,
    setKind: z.enum(["warmup", "working", "backoff"]),
    reps: Count.nullable().default(null),
    loadKg: Load.nullable().default(null),
    loadConvention: z
      .enum(["external", "bodyweight", "assistance"])
      .default("external"),
    rpe: Effort.nullable().default(null),
    rir: Effort.nullable().default(null),
    status: z.enum(["completed", "failed", "skipped"]),
    completedAt: optionalInstant,
  })
  .strict();
const exercise = z
  .object({
    id: Id,
    prescribedExerciseId: optionalId,
    exerciseId: Id,
    sequence: Count,
    notes: Notes,
    substitutionReason: Notes,
    sets: z.array(set).max(100),
  })
  .strict()
  .refine(
    (v) =>
      uniqueBy(v.sets, (s) => s.id) && uniqueBy(v.sets, (s) => s.setNumber),
    "Duplicate set",
  );
const result = {
  plannedWorkoutId: optionalId,
  logicalWorkoutId: optionalId,
  trainingDate: Day,
  timezone: Zone,
  dateBasis: z.enum(["performedDate", "loggedDate"]).default("performedDate"),
  loggedAt: optionalInstant,
  durationS: Seconds.nullable().default(null),
  startedAt: optionalInstant,
  endedAt: optionalInstant,
  completionStatus: z.enum([
    "completed",
    "partial",
    "modified",
    "abandoned",
    "skipped",
  ]),
  sourceType: z.enum(["manual", "healthkit"]),
  sessionRpe: Effort.nullable().default(null),
  notes: Notes,
};
export const WorkoutInput = z
  .discriminatedUnion("discipline", [
    z
      .object({
        ...result,
        discipline: z.literal("running"),
        run: RunResultInput.nullable(),
      })
      .strict(),
    z
      .object({
        ...result,
        discipline: z.literal("strength"),
        exercises: z.array(exercise).max(100),
      })
      .strict(),
  ])
  .superRefine((v, ctx) => {
    if (
      v.discipline === "running" &&
      v.durationS !== null &&
      v.run &&
      v.durationS !== v.run.durationS
    )
      ctx.addIssue({
        code: "custom",
        message: "Session and run elapsed duration must agree",
      });
    if (
      v.startedAt &&
      v.endedAt &&
      Date.parse(v.startedAt) > Date.parse(v.endedAt)
    )
      ctx.addIssue({ code: "custom", message: "End precedes start" });
    if (
      v.discipline === "running" &&
      ((v.completionStatus === "skipped" && v.run !== null) ||
        (v.completionStatus !== "skipped" && v.run === null))
    )
      ctx.addIssue({
        code: "custom",
        message: "Running data must correspond to completion status",
      });
    if (
      v.discipline === "strength" &&
      (!uniqueBy(v.exercises, (e) => e.id) ||
        !uniqueBy(v.exercises, (e) => e.sequence) ||
        (v.completionStatus === "skipped" && v.exercises.length))
    )
      ctx.addIssue({ code: "custom", message: "Invalid strength results" });
  })
  .openapi("WorkoutResultInput");
export const SourceInput = z
  .object({
    provider: z.literal("healthkit"),
    externalId: z.string().min(1).max(200),
    fingerprint: z.string().min(1).max(200),
    workoutResultId: optionalId,
    sourceCreatedAt: optionalInstant,
    sourceUpdatedAt: optionalInstant,
    sourceDeletedAt: optionalInstant,
    importStatus: z.enum(["imported", "partial", "deleted", "error"]),
    matchStatus: z.enum(["unmatched", "suggested", "confirmed", "rejected"]),
    matchConfidence: z.number().min(0).max(1).nullable().default(null),
    matchedLogicalWorkoutId: optionalId,
    metadata: z
      .object({
        appName: z.string().max(200).optional(),
        bundleIdentifier: z.string().max(200).optional(),
        deviceName: z.string().max(200).optional(),
      })
      .strict()
      .default({}),
  })
  .strict()
  .openapi("ActivitySourceInput");
export type Workout = z.infer<typeof WorkoutInput>;
