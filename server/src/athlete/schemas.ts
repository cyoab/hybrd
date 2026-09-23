import { z } from "@hono/zod-openapi";
import {
  Day,
  Features,
  Id,
  Notes,
  optionalId,
  optionalInstant,
  orderedRange,
  Zone,
} from "../domain/schemas";

export const ProfileInput = z
  .object({
    timezone: Zone,
    locale: z.string().min(2).max(35),
    distanceUnit: z.enum(["km", "mi"]),
    loadUnit: z.enum(["kg", "lb"]),
    weekStartsOn: z.number().int().min(1).max(7),
    trainingDayBoundary: z
      .string()
      .regex(/^([01]\d|2[0-3]):[0-5]\d:[0-5]\d$/)
      .nullable()
      .default(null),
    cloudAiConsent: z.boolean().default(false),
  })
  .strict()
  .openapi("AthleteProfileInput");
export const PreferencesInput = z
  .object({
    priorityMode: z.enum(["balanced", "run_first", "strength_first", "custom"]),
    runPriorityWeight: z.number().min(0).max(1),
    strengthPriorityWeight: z.number().min(0).max(1),
    strengthObjective: z.enum([
      "strength",
      "hypertrophy",
      "maintenance",
      "mixed",
    ]),
    experienceLevel: z
      .enum(["beginner", "intermediate", "advanced"])
      .nullable()
      .default(null),
    notes: Notes,
  })
  .strict()
  .refine(
    (v) =>
      Math.abs(v.runPriorityWeight + v.strengthPriorityWeight - 1) < 0.00001,
    "Priority weights must sum to one",
  )
  .openapi("TrainingPreferencesInput");
export const GoalInput = z
  .object({
    discipline: z.enum(["running", "strength", "hybrid"]),
    goalType: z.string().min(1).max(64),
    status: z.enum(["active", "completed", "paused", "cancelled"]),
    targetDate: Day.nullable().default(null),
    targetValue: z.number().nonnegative().nullable().default(null),
    targetUnit: z
      .enum(["seconds", "meters", "kg", "reps"])
      .nullable()
      .default(null),
    priorityRank: z.number().int().min(1).max(100).nullable().default(null),
    metadata: z
      .object({
        raceDistanceM: z.number().int().positive().max(1000000).optional(),
        targetFinishSeconds: z.number().int().positive().optional(),
        exerciseId: Id.optional(),
        targetLoadKg: z.number().nonnegative().optional(),
        targetReps: z.number().int().positive().optional(),
      })
      .strict()
      .default({}),
  })
  .strict()
  .openapi("AthleteGoalInput");
export const AvailabilityRuleInput = z
  .object({
    dayOfWeek: z.number().int().min(1).max(7),
    available: z.boolean(),
    maxSessions: z.number().int().min(0).max(3),
    minSessionMinutes: z
      .number()
      .int()
      .min(0)
      .max(1440)
      .nullable()
      .default(null),
    maxSessionMinutes: z
      .number()
      .int()
      .min(0)
      .max(1440)
      .nullable()
      .default(null),
    preference: z.enum(["preferred", "neutral", "avoid"]),
  })
  .strict()
  .refine(
    (v) =>
      orderedRange(v.minSessionMinutes, v.maxSessionMinutes) &&
      (v.available || v.maxSessions === 0),
    "Invalid availability constraints",
  )
  .openapi("AvailabilityRuleInput");
export const AvailabilityOverrideInput = z
  .object({
    date: Day,
    available: z.boolean(),
    maxSessions: z.number().int().min(0).max(3).nullable().default(null),
    maxSessionMinutes: z
      .number()
      .int()
      .min(0)
      .max(1440)
      .nullable()
      .default(null),
    reason: Notes,
  })
  .strict()
  .refine(
    (v) => v.available || !v.maxSessions,
    "Unavailable days cannot allow sessions",
  )
  .openapi("AvailabilityOverrideInput");
export const BaselineInput = z
  .object({
    periodStart: Day,
    periodEnd: Day,
    schemaVersion: z.literal(1),
    metrics: Features,
    confidence: Features,
    source: z.enum(["healthkit", "strava", "manual", "mixed"]),
    confirmedAt: optionalInstant,
  })
  .strict()
  .refine((v) => v.periodStart <= v.periodEnd, "Invalid baseline period")
  .openapi("BaselineInput");
export const EquipmentInput = z
  .object({ equipmentId: Id, available: z.boolean() })
  .strict()
  .openapi("AthleteEquipmentInput");
export const ExercisePreferenceInput = z
  .object({
    exerciseId: Id,
    preference: z.enum(["preferred", "neutral", "avoid", "exclude"]),
    notes: Notes,
  })
  .strict()
  .openapi("ExercisePreferenceInput");
export const PlanningContextInput = z
  .object({
    baselineSnapshotId: optionalId,
    schemaVersion: z.literal(1),
    policyVersionId: Id,
    snapshot: z
      .object({
        goals: z.array(GoalInput).max(30),
        preferences: PreferencesInput,
        availabilityRules: z.array(AvailabilityRuleInput).max(7),
        availabilityOverrides: z.array(AvailabilityOverrideInput).max(365),
        equipmentIds: z.array(Id).max(100),
        recentFeatures: Features,
      })
      .strict(),
  })
  .strict()
  .openapi("PlanningContextInput");
