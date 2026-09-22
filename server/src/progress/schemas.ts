import { z } from "@hono/zod-openapi";
import { Day, Id, Instant, Revision, Zone } from "../domain/schemas";
import { addDays } from "./calendar";

export const RULES_VERSION = 1;
export const SCHEMA_VERSION = 1;
export const RunType = z.enum([
  "easy",
  "recovery",
  "long",
  "tempo",
  "intervals",
  "hills",
  "progression",
  "custom",
]);
const dateBasis = z.enum(["performedDate", "loggedDate"]);
export const ProgressZone = Zone.refine(
  (v) => !/^[+-]/.test(v),
  "Expected a named IANA timezone",
);
export const SummaryQuery = z
  .object({
    periodDays: z.coerce
      .number()
      .pipe(z.union([z.literal(7), z.literal(28), z.literal(84)]))
      .default(28),
    timezone: ProgressZone.default("UTC"),
  })
  .strict()
  .openapi("ProgressSummaryQuery");
const pagination = {
  cursor: z.string().min(1).max(2048).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  timezone: ProgressZone.default("UTC"),
};
export const ComparisonQuery = z
  .object(pagination)
  .strict()
  .openapi("ProgressComparisonQuery");
export const ActivityQuery = z
  .object({ ...pagination, from: Day, to: Day })
  .strict()
  .refine(
    (v) => v.from <= v.to && v.to <= addDays(v.from, 365),
    "Expected an ordered window of at most 366 calendar days",
  )
  .openapi("ProgressActivityQuery");
export const ComparisonParams = z.object({
  comparisonKey: z.string().regex(/^[a-f0-9]{64}$/),
});
export const TotalsSchema = z
  .object({
    runMeters: z.number().nonnegative(),
    strengthSets: z.number().int().nonnegative(),
    activeSeconds: z.number().nonnegative(),
    sessions: z.number().int().nonnegative(),
    runSessions: z.number().int().nonnegative(),
    liftSessions: z.number().int().nonnegative(),
    activeDays: z.number().int().nonnegative(),
  })
  .openapi("ProgressTotals");
export type Totals = z.infer<typeof TotalsSchema>;
export const DaySchema = TotalsSchema.extend({ date: Day }).openapi(
  "ProgressDay",
);
export type ProgressDay = z.infer<typeof DaySchema>;
export const ActivitySchema = z
  .object({
    resultId: Id,
    revision: Revision,
    trainingDate: Day,
    timezone: Zone,
    dateBasis,
    discipline: z.enum(["running", "strength"]),
    completionStatus: z.string(),
    title: z.string(),
    loggedAt: Instant.nullable(),
    completedAt: Instant.nullable(),
    runMeters: z.number().nonnegative(),
    strengthSets: z.number().int().nonnegative(),
    activeSeconds: z.number().nonnegative(),
    source: z.object({
      type: z.string(),
      records: z.number().int(),
      unresolvedMatches: z.number().int(),
      deletedRecords: z.number().int(),
    }),
    flags: z.array(z.string()),
  })
  .openapi("ProgressActivity");
export type Activity = z.infer<typeof ActivitySchema>;
export const PointSchema = z
  .object({
    resultId: Id,
    trainingDate: Day,
    occurredAt: Instant.nullable(),
    value: z.number().nonnegative(),
  })
  .openapi("ProgressComparisonPoint");
export type Point = z.infer<typeof PointSchema>;
export const GroupSchema = z
  .discriminatedUnion("kind", [
    z.object({
      kind: z.literal("running"),
      runType: RunType,
      distanceM: z.number().int().min(1000),
    }),
    z.object({
      kind: z.literal("strength"),
      exerciseId: Id,
      exerciseName: z.string(),
      reps: z.number().int().min(1).max(100),
      loadConvention: z.enum(["external", "bodyweight"]),
    }),
  ])
  .openapi("ProgressComparisonGroup");
export type Group = z.infer<typeof GroupSchema>;
export const ComparisonSchema = z
  .object({
    key: z.string(),
    group: GroupSchema,
    unit: z.enum(["secondsPerKilometer", "kilograms"]),
    first: PointSchema,
    latest: PointSchema,
    best: PointSchema,
    sampleCount: z.number().int(),
    chartPoints: z.array(PointSchema).max(32),
    hasMore: z.boolean(),
    change: z.object({
      absolute: z.number(),
      percent: z.number().nullable(),
      direction: z.enum(["improved", "regressed", "steady"]),
    }),
  })
  .openapi("ProgressComparison");
export type Comparison = z.infer<typeof ComparisonSchema>;
export const MilestoneSchema = z
  .object({
    key: z.string(),
    rulesVersion: z.literal(1),
    requirement: z.string(),
    target: z.number(),
    current: z.number(),
    unit: z.enum(["days", "disciplines", "meters", "sets"]),
    earnedAt: Instant.nullable(),
    earnedOn: Day.nullable(),
    evidenceResultId: Id.nullable(),
  })
  .openapi("ProgressMilestone");
export type Milestone = z.infer<typeof MilestoneSchema>;
export const MetadataSchema = z.object({
  schemaVersion: z.literal(1),
  rulesVersion: z.literal(1),
  asOf: Instant,
  timezone: Zone,
  dateBasis: z.enum(["performedDate", "loggedDate", "mixed"]),
  dataRevision: Revision,
  projectionSequence: Revision,
  freshness: z.literal("current"),
});
export const SummarySchema = MetadataSchema.extend({
  periodDays: z.union([z.literal(7), z.literal(28), z.literal(84)]),
  range: z.object({
    startDate: Day,
    endDateInclusive: Day,
    includesPartialToday: z.literal(true),
    previousStartDate: Day,
    previousEndDateInclusive: Day,
  }),
  totals: z.object({
    current: TotalsSchema,
    previous: TotalsSchema,
    lifetime: TotalsSchema,
    percentChange: z.object({
      runMeters: z.number().nullable(),
      strengthSets: z.number().nullable(),
      activeSeconds: z.number().nullable(),
      sessions: z.number().nullable(),
      runSessions: z.number().nullable(),
      liftSessions: z.number().nullable(),
      activeDays: z.number().nullable(),
    }),
  }),
  series: z.array(DaySchema).max(84),
  activityDays: z.array(DaySchema).length(28),
  journey: z.object({
    trainingDays: z.number().int(),
    level: z.number().int(),
    stepsInLevel: z.number().int(),
    stepsToNextLevel: z.number().int(),
  }),
  milestones: z.array(MilestoneSchema).length(8),
  comparisons: z.array(ComparisonSchema).max(2),
  recentActivity: z.array(ActivitySchema).max(3),
  exclusions: z.record(z.string(), z.number().int().nonnegative()),
}).openapi("ProgressSummary");
export const ComparisonPageSchema = MetadataSchema.extend({
  comparison: ComparisonSchema,
  points: z.array(PointSchema).max(100),
  nextCursor: z.string().nullable(),
}).openapi("ProgressComparisonPage");
export const ActivityPageSchema = MetadataSchema.extend({
  activity: z.array(ActivitySchema).max(100),
  nextCursor: z.string().nullable(),
}).openapi("ProgressActivityPage");
export type Summary = z.infer<typeof SummarySchema>;
