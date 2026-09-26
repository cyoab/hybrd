import type { z } from "@hono/zod-openapi";
import { ApiError } from "../api/errors";
import { AthleteDetailsInput, type Provenance } from "../athlete/details";
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
import {
  catalogReference,
  emit,
  hash,
  insertRow,
  owned,
  type Row,
  type Tx,
  updateRow,
} from "../db/store";
import { entityTables } from "../domain/read";
import { BlockInput } from "../plans/schemas";
import { activatePlan, createPlan } from "../plans/service";
import { queueWorkout } from "../strava/queue";
import { SourceInput, WorkoutInput } from "../workouts/schemas";
import { writeWorkoutChildren } from "../workouts/service";
import {
  CoachThreadInput,
  type Mutation,
  ProposalReviewInput,
} from "./schemas";

const inputs: Record<string, z.ZodType> = {
  athlete: ProfileInput,
  athlete_details: AthleteDetailsInput,
  athlete_goal: GoalInput,
  training_preferences: PreferencesInput,
  availability_rule: AvailabilityRuleInput,
  availability_override: AvailabilityOverrideInput,
  baseline_snapshot: BaselineInput,
  planning_context_snapshot: PlanningContextInput,
  athlete_equipment: EquipmentInput,
  exercise_preference: ExercisePreferenceInput,
  training_block: BlockInput,
  workout_result: WorkoutInput,
  activity_source_record: SourceInput,
  coach_thread: CoachThreadInput,
  action_proposal: ProposalReviewInput,
};
const immutable = new Set([
  "baseline_snapshot",
  "planning_context_snapshot",
  "plan_version",
]);
export async function applyMutation(sql: Tx, athlete: Row, mutation: Mutation) {
  const athleteId = String(athlete.id),
    id = mutation.entityId,
    table = entityTables[mutation.entityType];
  const [existing] = await sql<
    Row[]
  >`select * from ${sql(table)} where id=${id}`;
  if (
    existing &&
    (mutation.entityType === "athlete"
      ? existing.id !== athleteId
      : existing.athlete_id !== athleteId)
  )
    throw new ApiError(
      409,
      "ENTITY_ID_UNAVAILABLE",
      "Use a different record ID.",
    );
  if (
    mutation.entityType === "athlete" &&
    (id !== athleteId || mutation.operation !== "update")
  )
    throw new ApiError(
      400,
      "INVALID_OPERATION",
      "An athlete may only update their own profile.",
    );
  if (
    ["training_preferences", "athlete_details"].includes(mutation.entityType) &&
    id !== athleteId
  )
    throw new ApiError(
      400,
      "INVALID_ENTITY_ID",
      "Training preferences and athlete details use the athlete ID.",
    );
  if (mutation.operation === "activate_plan") {
    if (mutation.entityType !== "plan_version")
      throw new ApiError(
        400,
        "INVALID_OPERATION",
        "Only plans can be activated.",
      );
    const plan = await activatePlan(sql, athleteId, id, mutation.payload);
    await emit(
      sql,
      athleteId,
      "plan_version",
      id,
      "upsert",
      String(plan.revision),
    );
    return String(plan.revision);
  }
  if (mutation.operation === "create") {
    if (mutation.baseRevision !== null || existing)
      throw new ApiError(
        409,
        "REVISION_CONFLICT",
        "The record already exists or create has a base revision.",
      );
    if (mutation.entityType === "action_proposal")
      throw new ApiError(
        400,
        "INVALID_OPERATION",
        "Proposals are created by the coach gateway.",
      );
    if (mutation.entityType === "plan_version") {
      const plan = await createPlan(sql, athleteId, id, mutation.payload);
      await emit(
        sql,
        athleteId,
        "plan_version",
        id,
        "upsert",
        String(plan.revision),
      );
      return String(plan.revision);
    }
  } else {
    if (!existing)
      throw new ApiError(404, "NOT_FOUND", "The record is unavailable.");
    if (immutable.has(mutation.entityType))
      throw new ApiError(
        409,
        "IMMUTABLE_RECORD",
        "Create a new snapshot or plan version instead of editing history.",
      );
    if (String(existing.revision) !== mutation.baseRevision)
      throw new ApiError(
        409,
        "REVISION_CONFLICT",
        "The record changed on another device.",
      );
  }
  const revision = String(
    existing ? BigInt(String(existing.revision)) + 1n : 1n,
  );
  if (mutation.operation === "delete") {
    if (mutation.entityType === "action_proposal")
      throw new ApiError(
        400,
        "INVALID_OPERATION",
        "Reject the proposal instead.",
      );
    if (
      mutation.entityType === "training_block" &&
      existing?.active_plan_version_id
    )
      throw new ApiError(
        409,
        "BLOCK_HAS_HISTORY",
        "Cancel the block to preserve its accepted history.",
      );
    await updateRow(sql, table, id, {
      deletedAt: new Date(),
      updatedAt: new Date(),
      revision,
    });
    // Deleting a thread removes its visible transcript/proposals through tombstones.
    if (mutation.entityType === "coach_thread") {
      for (const childType of ["coach_message", "action_proposal"] as const) {
        const rows =
          await sql`update ${sql(entityTables[childType])} set deleted_at=now(),updated_at=now(),revision=revision+1 where thread_id=${id} and athlete_id=${athleteId} and deleted_at is null returning id,revision::text`;
        for (const row of rows)
          await emit(
            sql,
            athleteId,
            childType,
            String(row.id),
            "delete",
            String(row.revision),
          );
      }
    }
    await emit(sql, athleteId, mutation.entityType, id, "delete", revision);
    return revision;
  }
  const schema = inputs[mutation.entityType];
  if (!schema)
    throw new ApiError(400, "INVALID_OPERATION", "Unsupported mutation.");
  let data = schema.parse(mutation.payload) as Row;
  if (mutation.entityType === "athlete_details") {
    const details = AthleteDetailsInput.parse(data).details;
    for (const record of details.strengthRecords)
      await catalogReference(sql, "exercises", record.exerciseId);
    // Imported provenance is server-managed. Preserve it only for unchanged facts.
    const previous = (existing?.details ?? {}) as Row;
    data.provenance = (
      (existing?.provenance ?? []) as z.infer<typeof Provenance>[]
    ).filter(
      (p) =>
        p.field in details &&
        hash(previous[p.field] ?? null) ===
          hash((details as Row)[p.field] ?? null),
    );
  }
  if (mutation.entityType === "training_preferences") {
    const preferences = PreferencesInput.parse(data);
    for (const id of preferences.onboarding?.focusMuscleIds ?? []) {
      const [muscle] = await sql`select id from muscle_groups where id=${id}`;
      if (!muscle)
        throw new ApiError(400, "INVALID_REFERENCE", "Unknown muscle group.");
    }
  }
  if (data.exerciseId)
    await catalogReference(sql, "exercises", String(data.exerciseId));
  if (data.equipmentId)
    await catalogReference(sql, "equipment", String(data.equipmentId));
  if (mutation.entityType === "planning_context_snapshot") {
    if (data.baselineSnapshotId)
      await owned(
        sql,
        "baseline_snapshots",
        String(data.baselineSnapshotId),
        athleteId,
      );
    const [policy] =
      await sql`select id from training_policy_versions where id=${String(data.policyVersionId)} and status in ('published','retired')`;
    if (!policy)
      throw new ApiError(
        400,
        "POLICY_UNAVAILABLE",
        "Reference a published policy version.",
      );
    const snapshot = PlanningContextInput.parse(data).snapshot;
    if (snapshot.athleteDetailsId)
      await owned(sql, "athlete_details", snapshot.athleteDetailsId, athleteId);
    data.checksum = `sha256:${hash(data.snapshot)}`;
  }
  if (mutation.entityType === "training_block" && existing) {
    const [outside] =
      await sql`select w.id from planned_workouts w join plan_versions p on p.id=w.plan_version_id where p.training_block_id=${id} and (w.scheduled_date<${String(data.startDate)} or w.scheduled_date>${String(data.endDate)}) limit 1`;
    if (outside || (existing.active_plan_version_id && data.status === "draft"))
      throw new ApiError(
        409,
        "BLOCK_HAS_HISTORY",
        "Block edits must preserve the accepted schedule.",
      );
  }
  if (mutation.entityType === "activity_source_record") {
    const input = SourceInput.parse(data);
    if (input.workoutResultId) {
      const result = await owned(
        sql,
        "workout_results",
        input.workoutResultId,
        athleteId,
      );
      if (
        input.matchStatus === "confirmed" &&
        result.logical_workout_id !== input.matchedLogicalWorkoutId
      )
        throw new ApiError(
          400,
          "MATCH_MISMATCH",
          "The confirmed source and workout must agree on their prescription.",
        );
    }
    if (input.matchedLogicalWorkoutId) {
      const [logical] =
        await sql`select w.id from planned_workouts w join plan_versions p on p.id=w.plan_version_id where w.logical_workout_id=${input.matchedLogicalWorkoutId} and p.athlete_id=${athleteId} limit 1`;
      if (!logical)
        throw new ApiError(
          400,
          "INVALID_REFERENCE",
          "The matched session is unavailable.",
        );
    }
    const [duplicate] =
      await sql`select id from activity_source_records where athlete_id=${athleteId} and provider=${input.provider} and (external_id=${input.externalId} or fingerprint=${input.fingerprint}) and id<>${id} limit 1`;
    if (duplicate)
      throw new ApiError(
        409,
        "DUPLICATE_SOURCE",
        "This external activity has already been imported.",
      );
  }
  if (mutation.entityType === "action_proposal") {
    if (
      !existing ||
      existing.deleted_at ||
      new Date(String(existing.expires_at)) <= new Date() ||
      !["pending", "accepted"].includes(String(existing.status))
    )
      throw new ApiError(
        409,
        "PROPOSAL_STALE",
        "This proposal can no longer be reviewed.",
      );
    const [head] =
      await sql`select b.active_plan_version_id from training_blocks b join plan_versions p on p.training_block_id=b.id where p.id=${String(existing.base_plan_version_id)} and b.athlete_id=${athleteId}`;
    if (!head || head.active_plan_version_id !== existing.base_plan_version_id)
      throw new ApiError(
        409,
        "PLAN_HEAD_CONFLICT",
        "Re-evaluate the proposal against the current plan.",
      );
    data.acceptedAt = data.status === "accepted" ? new Date() : null;
  }
  if (mutation.entityType === "workout_result") {
    // The root revision protects a full replacement of the result aggregate.
    const { run: _run, exercises: _exercises, ...root } = data;
    data = root;
    if (existing && existing.discipline !== data.discipline)
      throw new ApiError(
        409,
        "DISCIPLINE_IMMUTABLE",
        "Create a new result to change discipline.",
      );
  }
  if (existing)
    await updateRow(sql, table, id, {
      ...data,
      revision,
      updatedAt: new Date(),
      deletedAt: null,
    });
  else await insertRow(sql, table, { ...data, id, athleteId });
  if (mutation.entityType === "workout_result") {
    await writeWorkoutChildren(sql, athleteId, id, mutation.payload);
    await queueWorkout(sql, athleteId, id);
  }
  await emit(sql, athleteId, mutation.entityType, id, "upsert", revision);
  return revision;
}
