import { z } from "@hono/zod-openapi";
import { AthleteDetails, Experience, ImportDecision } from "../athlete/details";
import { ProfileInput } from "../athlete/schemas";
import { Day, Id, Instant, Revision, uniqueBy } from "../domain/schemas";
export const Step = z.enum([
  "connections",
  "identity",
  "goals",
  "baseline",
  "body",
  "schedule",
  "equipment",
  "focus",
  "readiness",
  "review",
  "preparing",
  "membership",
]);
export const Draft = z
  .object({
    schemaVersion: z.literal(1),
    profile: ProfileInput.nullable(),
    details: AthleteDetails,
    runningGoal: z
      .enum(["fitness", "5k", "10k", "half_marathon", "marathon"])
      .nullable(),
    strengthGoal: z.enum(["strength", "hypertrophy", "maintenance"]).nullable(),
    raceDate: Day.nullable(),
    priority: z.enum(["balanced", "run_first", "strength_first"]).nullable(),
    runningLevel: Experience.nullable(),
    strengthLevel: Experience.nullable(),
    weeklyDistanceM: z.number().min(0).max(250000).nullable(),
    currentStrengthSessionsPerWeek: z.number().min(0).max(7).nullable(),
    baselinePeriod: z
      .object({ start: Day, end: Day })
      .strict()
      .refine((v) => v.start <= v.end)
      .nullable(),
    availableDays: z
      .array(z.number().int().min(1).max(7))
      .max(7)
      .refine((v) => uniqueBy(v, (x) => x))
      .nullable(),
    desiredStrengthSessionsPerWeek: z.number().int().min(1).max(4).nullable(),
    sessionMinutes: z
      .union([
        z.literal(30),
        z.literal(45),
        z.literal(60),
        z.literal(75),
        z.literal(90),
      ])
      .nullable(),
    equipmentIds: z
      .array(Id)
      .max(100)
      .refine((v) => uniqueBy(v, (x) => x))
      .nullable(),
    equipmentConfirmed: z.boolean(),
    focusMuscleIds: z
      .array(Id)
      .max(10)
      .refine((v) => uniqueBy(v, (x) => x))
      .nullable(),
    readiness: z.enum(["ready", "returning", "adjusting"]).nullable(),
    context: z.string().max(300).nullable(),
    wantsHealth: z.boolean().nullable(),
    wantsStrava: z.boolean().nullable(),
    membership: z.enum(["monthly", "annual"]).nullable(),
    importDecisions: z
      .array(ImportDecision)
      .max(18)
      .refine(
        (v) => uniqueBy(v, (x) => x.field),
        "Select one source/decision per field",
      ),
  })
  .strict()
  .openapi("OnboardingDraft");
export const SaveDraftInput = z
  .object({ baseRevision: Revision.nullable(), step: Step, draft: Draft })
  .strict()
  .openapi("SaveOnboardingDraft");
export const CompleteInput = z
  .object({
    draftRevision: Revision,
    deviceId: Id,
    catalogVersion: z.number().int().positive(),
    policyVersionId: Id,
  })
  .strict()
  .openapi("CompleteOnboarding");
export const SavedRef = z.object({
  entityType: z.string(),
  id: Id,
  revision: Revision,
});
export const Receipt = z
  .object({
    submissionId: Id,
    choices: z.object({
      wantsHealth: z.boolean().nullable(),
      wantsStrava: z.boolean().nullable(),
      membership: z.enum(["monthly", "annual"]).nullable(),
    }),
    completedAt: Instant,
    draftRevision: Revision,
    catalogVersion: z.number().int(),
    policyVersionId: Id,
    athleteDetails: SavedRef,
    baseline: SavedRef,
    planningContext: SavedRef,
    saved: z.array(SavedRef),
    latestSequence: Revision,
    planning: z.object({
      status: z.enum(["ready_for_local_planner", "unsupported_baseline"]),
      reason: z.enum(["weekly_distance_outside_planner_range"]).nullable(),
      minimumWeeklyDistanceM: z.number().int(),
      maximumWeeklyDistanceM: z.number().int(),
    }),
  })
  .openapi("OnboardingCompletionReceipt");
export const ReviewIssue = z.object({
  field: z.string(),
  code: z.enum(["IMPORT_PREVIEW_EXPIRED", "IMPORT_REVIEW_REQUIRED"]),
});
export const OnboardingState = z
  .object({
    schemaVersion: z.literal(1),
    status: z.enum(["not_started", "draft", "completed"]),
    draft: Draft.nullable(),
    draftRevision: Revision.nullable(),
    step: Step.nullable(),
    completion: Receipt.nullable(),
    reviewIssues: z.array(ReviewIssue),
  })
  .openapi("OnboardingState");
export const DraftSaved = z
  .object({ draftRevision: Revision })
  .openapi("OnboardingDraftSaved");
export type DraftData = z.infer<typeof Draft>;
