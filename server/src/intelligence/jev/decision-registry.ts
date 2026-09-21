import { z } from "@hono/zod-openapi";

export const runningLoadChoices = [
  "reduce_significantly",
  "reduce_slightly",
  "hold",
  "increase_slightly",
  "increase_moderately",
] as const;

export const RunningLoadContextSchema = z
  .object({
    completionRate: z.number().min(0).max(1),
    weeklyDistanceKm: z.number().nonnegative(),
    previousWeeklyDistanceKm: z.number().nonnegative(),
    keyRunCompletionRate: z.number().min(0).max(1),
    easyRunRpeTrend: z.number().nullable(),
    missedSessionsLast14d: z.number().int().nonnegative(),
    strengthPerformanceTrend: z.number().nullable(),
    raceWeeksRemaining: z.number().int().nonnegative().nullable(),
  })
  .strict()
  .openapi("RunningLoadContext");

export const DecisionRequestSchema = z
  .object({
    decisionType: z.literal("next_week_running_load"),
    schemaVersion: z.literal(1),
    context: RunningLoadContextSchema,
  })
  .strict()
  .openapi("DecisionRequest");

export const decisionRegistry = {
  next_week_running_load: {
    schemaVersion: 1,
    context: RunningLoadContextSchema,
    choices: runningLoadChoices,
  },
} as const;
