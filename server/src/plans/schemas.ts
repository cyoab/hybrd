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
  orderedRange,
  Seconds,
  uniqueBy,
  Zone,
} from "../domain/schemas";

export const BlockInput = z
  .object({
    name: z.string().min(1).max(200),
    startDate: Day,
    endDate: Day,
    phase: z.enum(["build", "maintain", "deload", "taper", "recovery"]),
    status: z.enum(["draft", "active", "completed", "cancelled"]),
  })
  .strict()
  .refine((v) => v.startDate <= v.endDate, "Invalid block dates")
  .openapi("TrainingBlockInput");
const targets = {
  distanceM: Distance.nullable().default(null),
  durationS: Seconds.nullable().default(null),
  paceMinSPerKm: z.number().positive().max(7200).nullable().default(null),
  paceMaxSPerKm: z.number().positive().max(7200).nullable().default(null),
  hrMinBpm: z.number().int().min(20).max(250).nullable().default(null),
  hrMaxBpm: z.number().int().min(20).max(250).nullable().default(null),
  rpeMin: Effort.nullable().default(null),
  rpeMax: Effort.nullable().default(null),
};
export const step = z
  .object({
    id: Id,
    sequence: Count,
    stepKind: z.enum([
      "warmup",
      "work",
      "recovery",
      "cooldown",
      "steady",
      "stride",
    ]),
    ...targets,
    notes: Notes,
  })
  .strict()
  .refine(
    (v) =>
      orderedRange(v.paceMinSPerKm, v.paceMaxSPerKm) &&
      orderedRange(v.hrMinBpm, v.hrMaxBpm) &&
      orderedRange(v.rpeMin, v.rpeMax) &&
      (Boolean(v.distanceM) || Boolean(v.durationS)),
    "Invalid running step targets",
  );
export const runBlock = z
  .object({
    id: Id,
    sequence: Count,
    repeatCount: z.number().int().min(1).max(100),
    label: z.string().max(200).nullable().default(null),
    steps: z.array(step).min(1).max(50),
  })
  .strict()
  .refine(
    (v) =>
      uniqueBy(v.steps, (s) => s.id) && uniqueBy(v.steps, (s) => s.sequence),
    "Duplicate step identity or order",
  );
export const RunPrescriptionInput = z
  .object({
    primaryTargetType: z.enum(["pace", "heart_rate", "rpe", "mixed", "open"]),
    notes: Notes,
    blocks: z.array(runBlock).min(1).max(50),
  })
  .strict()
  .refine(
    (v) =>
      uniqueBy(v.blocks, (b) => b.id) && uniqueBy(v.blocks, (b) => b.sequence),
    "Duplicate run block",
  );
export const set = z
  .object({
    id: Id,
    setNumber: Count,
    setKind: z.enum(["warmup", "working", "backoff"]),
    repsMin: Count.nullable().default(null),
    repsMax: Count.nullable().default(null),
    loadKg: Load.nullable().default(null),
    loadPercentE1rm: z.number().min(0).max(150).nullable().default(null),
    rpeMin: Effort.nullable().default(null),
    rpeMax: Effort.nullable().default(null),
    rirMin: Effort.nullable().default(null),
    rirMax: Effort.nullable().default(null),
    restS: Seconds.nullable().default(null),
    notes: Notes,
  })
  .strict()
  .refine(
    (v) =>
      orderedRange(v.repsMin, v.repsMax) &&
      orderedRange(v.rpeMin, v.rpeMax) &&
      orderedRange(v.rirMin, v.rirMax),
    "Invalid strength set range",
  );
export const exercise = z
  .object({
    id: Id,
    exerciseId: Id,
    sequence: Count,
    supersetGroupId: optionalId,
    substitutionAllowed: z.boolean(),
    notes: Notes,
    sets: z.array(set).min(1).max(50),
    substitutions: z
      .array(
        z
          .object({ exerciseId: Id, priority: Count, rationale: Notes })
          .strict(),
      )
      .max(10)
      .default([]),
  })
  .strict()
  .refine(
    (v) =>
      uniqueBy(v.sets, (s) => s.id) &&
      uniqueBy(v.sets, (s) => s.setNumber) &&
      uniqueBy(v.substitutions, (s) => s.exerciseId),
    "Duplicate strength set or substitution",
  );
export const StrengthPrescriptionInput = z
  .object({
    sessionFocus: z.string().min(1).max(64),
    notes: Notes,
    exercises: z.array(exercise).min(1).max(40),
  })
  .strict()
  .refine(
    (v) =>
      uniqueBy(v.exercises, (e) => e.id) &&
      uniqueBy(v.exercises, (e) => e.sequence),
    "Duplicate exercise identity or order",
  );
const planned = {
  id: Id,
  logicalWorkoutId: Id,
  workoutType: z.string().min(1).max(64),
  scheduledDate: Day,
  scheduledStartAt: optionalInstant,
  timezone: Zone,
  title: z.string().min(1).max(200),
  purpose: Notes,
  priority: z.enum(["key", "supporting", "optional"]),
  estimatedDurationS: Seconds.nullable().default(null),
  plannedDistanceM: Distance.nullable().default(null),
  instructions: Notes,
};
export const PlannedWorkoutInput = z
  .discriminatedUnion("discipline", [
    z
      .object({
        ...planned,
        discipline: z.literal("running"),
        run: RunPrescriptionInput,
      })
      .strict(),
    z
      .object({
        ...planned,
        discipline: z.literal("strength"),
        strength: StrengthPrescriptionInput,
      })
      .strict(),
  ])
  .openapi("PlannedWorkoutInput");
export const PlanInput = z
  .object({
    trainingBlockId: Id,
    basePlanVersionId: optionalId,
    planningContextSnapshotId: Id,
    policyVersionId: Id,
    origin: z.enum(["initial", "manual_edit", "adaptive", "replan", "coach"]),
    summary: Notes,
    workouts: z.array(PlannedWorkoutInput).min(1).max(300),
  })
  .strict()
  .refine(
    (v) =>
      uniqueBy(v.workouts, (w) => w.id) &&
      uniqueBy(v.workouts, (w) => w.logicalWorkoutId),
    "Duplicate workout identity",
  )
  .openapi("PlanVersionInput");
export const ActivatePlanInput = z
  .object({
    expectedActivePlanVersionId: optionalId,
    accepted: z.literal(true),
    reasonCode: z.string().min(1).max(100),
    explanation: z.string().min(1).max(4000),
    proposalId: optionalId,
  })
  .strict()
  .openapi("ActivatePlanInput");
export type Plan = z.infer<typeof PlanInput>;
