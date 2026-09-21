import { z } from "@hono/zod-openapi";
import {
  AvailabilityOverrideInput,
  AvailabilityRuleInput,
  BaselineInput,
  EquipmentInput,
  ExercisePreferenceInput,
  GoalInput,
  PlanningContextInput,
  PreferencesInput,
  ProfileInput,
} from "../athlete/schemas";
import { CanonicalSchemas } from "../domain/records";
import { Id, Revision } from "../domain/schemas";
import { ActivatePlanInput, BlockInput, PlanInput } from "../plans/schemas";
import { SourceInput, WorkoutInput } from "../workouts/schemas";
export const CoachThreadInput = z
  .object({ title: z.string().min(1).max(200).nullable() })
  .strict()
  .openapi("CoachThreadInput");
export const ProposalReviewInput = z
  .object({ status: z.enum(["accepted", "rejected"]) })
  .strict()
  .openapi("ProposalReviewInput");
const envelope = {
  id: Id,
  entityId: Id,
  operation: z.enum(["create", "update", "delete", "activate_plan"]),
  baseRevision: Revision.nullable(),
};
const empty = z.object({}).strict();
function variant<T extends string, S extends z.ZodType>(name: T, schema: S) {
  return z
    .object({
      ...envelope,
      entityType: z.literal(name),
      payload: z.union([schema, empty]),
    })
    .strict();
}
export const SyncMutationSchema = z
  .discriminatedUnion("entityType", [
    variant("athlete", ProfileInput),
    variant("athlete_goal", GoalInput),
    variant("training_preferences", PreferencesInput),
    variant("availability_rule", AvailabilityRuleInput),
    variant("availability_override", AvailabilityOverrideInput),
    variant("baseline_snapshot", BaselineInput),
    variant("planning_context_snapshot", PlanningContextInput),
    variant("athlete_equipment", EquipmentInput),
    variant("exercise_preference", ExercisePreferenceInput),
    variant("training_block", BlockInput),
    variant("plan_version", z.union([PlanInput, ActivatePlanInput])),
    variant("workout_result", WorkoutInput),
    variant("activity_source_record", SourceInput),
    variant("coach_thread", CoachThreadInput),
    variant("action_proposal", ProposalReviewInput),
  ])
  .openapi("SyncMutation");
export const SyncPushSchema = z
  .object({
    deviceId: Id,
    mutations: z.array(SyncMutationSchema).min(1).max(100),
  })
  .strict()
  .openapi("SyncPush");
export const SyncPullQuerySchema = z
  .object({
    deviceId: Id,
    cursor: Revision.default("0"),
    limit: z.coerce.number().int().min(1).max(100).default(50),
  })
  .openapi("SyncPullQuery");
export const MutationResultSchema = z
  .object({
    mutationId: Id,
    status: z.enum(["applied", "conflict", "rejected"]),
    entityRevision: Revision.nullable().optional(),
    error: z
      .object({
        code: z.string(),
        message: z.string(),
        serverRevision: Revision.optional(),
      })
      .optional(),
  })
  .openapi("MutationResult");
export const SyncPushResponse = z
  .object({ results: z.array(MutationResultSchema), serverSequence: Revision })
  .openapi("SyncPushResponse");
const changeEnvelope = {
  sequence: Revision,
  entityId: Id,
  operation: z.enum(["upsert", "delete"]),
  revision: Revision.nullable(),
};
function change<T extends keyof typeof CanonicalSchemas>(entityType: T) {
  return z.object({
    ...changeEnvelope,
    entityType: z.literal(entityType),
    payload: CanonicalSchemas[entityType].nullable(),
  });
}
export const SyncChangeSchema = z
  .discriminatedUnion("entityType", [
    change("athlete"),
    change("athlete_goal"),
    change("training_preferences"),
    change("availability_rule"),
    change("availability_override"),
    change("baseline_snapshot"),
    change("planning_context_snapshot"),
    change("athlete_equipment"),
    change("exercise_preference"),
    change("training_block"),
    change("plan_version"),
    change("workout_result"),
    change("activity_source_record"),
    change("plan_change_set"),
    change("coach_thread"),
    change("coach_message"),
    change("action_proposal"),
    change("structured_decision"),
    change("entitlement"),
  ])
  .openapi("SyncChange");
export const SyncPullResponse = z
  .object({
    changes: z.array(SyncChangeSchema),
    nextCursor: Revision,
    hasMore: z.boolean(),
  })
  .openapi("SyncPullResponse");
export const SyncAckInput = z
  .object({ deviceId: Id, cursor: Revision })
  .strict()
  .openapi("SyncAcknowledgement");
export type Mutation = z.infer<typeof SyncMutationSchema>;
export type MutationResult = z.infer<typeof MutationResultSchema>;
export type Push = z.infer<typeof SyncPushSchema>;
export type Pull = z.infer<typeof SyncPullQuerySchema>;
