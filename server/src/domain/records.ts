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
import { BlockInput, PlanInput } from "../plans/schemas";
import { SourceInput, WorkoutInput } from "../workouts/schemas";
import { Id, Instant, Revision } from "./schemas";

const mutable = {
  id: Id,
  createdAt: Instant,
  updatedAt: Instant,
  revision: Revision,
  deletedAt: Instant.nullable(),
};
const owned = { ...mutable, athleteId: Id };

const json = z.record(z.string(), z.unknown());
export const CanonicalSchemas = {
  athlete: ProfileInput.safeExtend(mutable).openapi("AthleteRecord"),
  athlete_goal: GoalInput.safeExtend(owned).openapi("GoalRecord"),
  training_preferences: PreferencesInput.safeExtend(owned).openapi(
    "TrainingPreferencesRecord",
  ),
  availability_rule: AvailabilityRuleInput.safeExtend(owned).openapi(
    "AvailabilityRuleRecord",
  ),
  availability_override: AvailabilityOverrideInput.safeExtend(owned).openapi(
    "AvailabilityOverrideRecord",
  ),
  baseline_snapshot: BaselineInput.safeExtend(owned).openapi("BaselineRecord"),
  planning_context_snapshot: PlanningContextInput.safeExtend({
    ...owned,
    checksum: z.string(),
  }).openapi("PlanningContextRecord"),
  athlete_equipment: EquipmentInput.safeExtend(owned).openapi(
    "AthleteEquipmentRecord",
  ),
  exercise_preference: ExercisePreferenceInput.safeExtend(owned).openapi(
    "ExercisePreferenceRecord",
  ),
  training_block: BlockInput.safeExtend({
    ...owned,
    activePlanVersionId: Id.nullable(),
  }).openapi("TrainingBlockRecord"),
  plan_version: PlanInput.safeExtend({
    ...owned,
    versionNumber: z.number().int(),
    status: z.enum(["draft", "active", "superseded", "rejected"]),
    activatedAt: Instant.nullable(),
  }).openapi("PlanVersionRecord"),
  workout_result: z
    .union([
      WorkoutInput.options[0].safeExtend(owned),
      WorkoutInput.options[1].safeExtend(owned),
    ])
    .openapi("WorkoutResultRecord"),
  activity_source_record: SourceInput.safeExtend(owned).openapi(
    "ActivitySourceRecord",
  ),
  plan_change_set: z
    .object({
      id: Id,
      athleteId: Id,
      fromPlanVersionId: Id.nullable(),
      toPlanVersionId: Id,
      origin: z.string(),
      reasonCode: z.string(),
      explanation: z.string(),
      material: z.boolean(),
      proposalId: Id.nullable(),
      acceptedAt: Instant,
      createdAt: Instant,
      items: z.array(
        z.object({
          id: Id,
          logicalWorkoutId: Id,
          changeType: z.enum([
            "added",
            "removed",
            "moved",
            "prescription_changed",
          ]),
          beforePlannedWorkoutId: Id.nullable(),
          afterPlannedWorkoutId: Id.nullable(),
          changes: json,
        }),
      ),
    })
    .openapi("PlanChangeRecord"),
  coach_thread: z
    .object({ ...owned, title: z.string().nullable() })
    .openapi("CoachThreadRecord"),
  coach_message: z
    .object({
      ...owned,
      threadId: Id,
      role: z.enum(["user", "assistant"]),
      content: z.string(),
      aiInvocationId: Id.nullable(),
    })
    .openapi("CoachMessageRecord"),
  action_proposal: z
    .object({
      ...owned,
      threadId: Id.nullable(),
      messageId: Id.nullable(),
      basePlanVersionId: Id.nullable(),
      actionType: z.enum([
        "move_workout",
        "substitute_exercise",
        "replan_block",
      ]),
      actionPayload: json,
      rationale: z.string(),
      status: z.enum(["pending", "accepted", "rejected", "applied"]),
      expiresAt: Instant,
      acceptedAt: Instant.nullable(),
      appliedPlanVersionId: Id.nullable(),
    })
    .openapi("ActionProposalRecord"),
  structured_decision: z
    .object({
      id: Id,
      athleteId: Id,
      invocationId: Id,
      decisionType: z.string(),
      selectedChoice: z.string(),
      result: json,
      createdAt: Instant,
    })
    .openapi("StructuredDecisionRecord"),
  entitlement: z
    .object({
      id: Id,
      athleteId: Id,
      entitlementKey: z.string(),
      status: z.enum(["active", "grace", "expired", "revoked"]),
      validUntil: Instant.nullable(),
      source: z.string(),
      revision: Revision,
      updatedAt: Instant,
    })
    .openapi("EntitlementRecord"),
} as const;
export const CatalogSchema = z
  .object({
    version: z.number().int(),
    exercises: z.array(
      z.object({
        id: Id,
        slug: z.string(),
        name: z.string(),
        movementPattern: z.string().nullable(),
        unilateral: z.boolean(),
        active: z.boolean(),
        metadata: json,
      }),
    ),
    equipment: z.array(
      z.object({ id: Id, slug: z.string(), name: z.string() }),
    ),
    muscleGroups: z.array(
      z.object({ id: Id, slug: z.string(), name: z.string() }),
    ),
    aliases: z.array(
      z.object({
        id: Id,
        exerciseId: Id,
        source: z.string(),
        alias: z.string(),
      }),
    ),
    exerciseMuscles: z.array(
      z.object({
        exerciseId: Id,
        muscleGroupId: Id,
        role: z.enum(["primary", "secondary"]),
      }),
    ),
    exerciseEquipment: z.array(
      z.object({ exerciseId: Id, equipmentId: Id, required: z.boolean() }),
    ),
  })
  .openapi("ExerciseCatalog");
