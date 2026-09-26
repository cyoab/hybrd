import { ApiError } from "../api/errors";
import {
  catalogReference,
  emit,
  hash,
  insertRow,
  owned,
  type Row,
  type Tx,
  updateRow,
  wire,
} from "../db/store";
import { readEntity, readWorkoutPrescription } from "../domain/read";
import { ActivatePlanInput, PlanInput } from "./schemas";

export async function createPlan(
  sql: Tx,
  athleteId: string,
  id: string,
  body: unknown,
) {
  const input = PlanInput.parse(body);
  const block = await owned(
    sql,
    "training_blocks",
    input.trainingBlockId,
    athleteId,
  );
  if (["completed", "cancelled"].includes(String(block.status)))
    throw new ApiError(
      409,
      "BLOCK_CLOSED",
      "A closed block cannot receive new plans.",
    );
  const context = await owned(
    sql,
    "planning_context_snapshots",
    input.planningContextSnapshotId,
    athleteId,
  );
  if (context.policy_version_id !== input.policyVersionId)
    throw new ApiError(
      400,
      "POLICY_MISMATCH",
      "Plan and context must reference the same policy.",
    );
  if (input.basePlanVersionId) {
    const base = await owned(
      sql,
      "plan_versions",
      input.basePlanVersionId,
      athleteId,
    );
    if (base.training_block_id !== input.trainingBlockId || !base.activated_at)
      throw new ApiError(
        400,
        "INVALID_BASE_PLAN",
        "The base must be an accepted version of this block.",
      );
  }
  const [{ next } = { next: 1 }] =
    await sql`select coalesce(max(version_number),0)+1 as next from plan_versions where training_block_id=${input.trainingBlockId}`;
  const { workouts, ...fields } = input;
  const plan = await insertRow(sql, "plan_versions", {
    ...fields,
    id,
    athleteId,
    versionNumber: next,
  });
  for (const workout of workouts) {
    const [other] =
      await sql`select w.id from planned_workouts w join plan_versions p on p.id=w.plan_version_id where p.athlete_id=${athleteId} and w.logical_workout_id=${workout.logicalWorkoutId} and (p.training_block_id<>${input.trainingBlockId} or w.discipline<>${workout.discipline}) limit 1`;
    if (other)
      throw new ApiError(
        409,
        "LOGICAL_WORKOUT_CONFLICT",
        "A logical workout must remain in the same block and discipline.",
      );

    if (
      workout.scheduledDate < String(wire(block).startDate) ||
      workout.scheduledDate > String(wire(block).endDate)
    )
      throw new ApiError(
        400,
        "OUTSIDE_BLOCK",
        "A scheduled workout falls outside the training block.",
      );
    const { run, strength, ...envelope } = {
      run: undefined,
      strength: undefined,
      ...workout,
    };
    await insertRow(sql, "planned_workouts", {
      ...envelope,
      planVersionId: id,
    });
    if (run) {
      const { blocks, ...prescription } = run;
      await insertRow(sql, "run_prescriptions", {
        ...prescription,
        plannedWorkoutId: workout.id,
      });
      for (const block of blocks) {
        const { steps, ...blockData } = block;
        await insertRow(sql, "run_prescription_blocks", {
          ...blockData,
          plannedWorkoutId: workout.id,
        });
        for (const step of steps)
          await insertRow(sql, "run_prescription_steps", {
            ...step,
            blockId: block.id,
          });
      }
    }
    if (strength) {
      const { exercises, ...prescription } = strength;
      await insertRow(sql, "strength_prescriptions", {
        ...prescription,
        plannedWorkoutId: workout.id,
      });
      for (const exercise of exercises) {
        await catalogReference(sql, "exercises", exercise.exerciseId);
        const { sets, substitutions, ...exerciseData } = exercise;
        await insertRow(sql, "strength_exercise_prescriptions", {
          ...exerciseData,
          plannedWorkoutId: workout.id,
        });
        for (const set of sets)
          await insertRow(sql, "strength_set_prescriptions", {
            ...set,
            exercisePrescriptionId: exercise.id,
          });
        for (const sub of substitutions) {
          await catalogReference(sql, "exercises", sub.exerciseId);
          await insertRow(sql, "strength_substitution_options", {
            exercisePrescriptionId: exercise.id,
            substituteExerciseId: sub.exerciseId,
            priority: sub.priority,
            rationale: sub.rationale,
          });
        }
      }
    }
  }
  return plan;
}

const structuralKeys = new Set([
  "id",
  "createdAt",
  "planVersionId",
  "plannedWorkoutId",
  "blockId",
  "exercisePrescriptionId",
]);
export function semantic(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(semantic);
  if (value && typeof value === "object")
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => !structuralKeys.has(key))
        .map(([key, v]) => [key, semantic(v)]),
    );
  return value;
}
export function planDiff(before: Row[], after: Row[]) {
  const old = new Map(before.map((w) => [String(w.logicalWorkoutId), w]));
  const next = new Map(after.map((w) => [String(w.logicalWorkoutId), w]));
  const changes: Row[] = [];
  for (const logicalWorkoutId of new Set([...old.keys(), ...next.keys()])) {
    const a = old.get(logicalWorkoutId),
      b = next.get(logicalWorkoutId);
    if (a && b && hash(semantic(a)) === hash(semantic(b))) continue;
    const onlyMoved =
      a &&
      b &&
      hash(
        semantic({
          ...a,
          scheduledDate: null,
          scheduledStartAt: null,
          timezone: null,
        }),
      ) ===
        hash(
          semantic({
            ...b,
            scheduledDate: null,
            scheduledStartAt: null,
            timezone: null,
          }),
        );
    changes.push({
      id: crypto.randomUUID(),
      logicalWorkoutId,
      changeType: !a
        ? "added"
        : !b
          ? "removed"
          : onlyMoved
            ? "moved"
            : "prescription_changed",
      beforePlannedWorkoutId: a?.id ?? null,
      afterPlannedWorkoutId: b?.id ?? null,
      changes: {
        before: a ? semantic(a) : null,
        after: b ? semantic(b) : null,
      },
    });
  }
  return changes;
}

export async function activatePlan(
  sql: Tx,
  athleteId: string,
  id: string,
  body: unknown,
  authorization?: { actionId: string },
) {
  const input = ActivatePlanInput.parse(body);
  const plan = await owned(sql, "plan_versions", id, athleteId);
  const block = await owned(
    sql,
    "training_blocks",
    String(plan.training_block_id),
    athleteId,
  );
  if (block.active_plan_version_id === id && plan.status === "active")
    return plan;
  if (plan.status !== "draft")
    throw new ApiError(
      409,
      "PLAN_IMMUTABLE",
      "Only a new draft version can be activated.",
    );
  if (
    block.active_plan_version_id !== input.expectedActivePlanVersionId ||
    plan.base_plan_version_id !== input.expectedActivePlanVersionId
  )
    throw new ApiError(
      409,
      "PLAN_HEAD_CONFLICT",
      "The active plan changed. Rebase before accepting this version.",
    );
  if (["completed", "cancelled"].includes(String(block.status)))
    throw new ApiError(409, "BLOCK_CLOSED", "The block is closed.");
  const before = input.expectedActivePlanVersionId
    ? ((
        await readEntity(
          sql,
          athleteId,
          "plan_version",
          input.expectedActivePlanVersionId,
        )
      )?.workouts as Row[])
    : [];
  const after = (await readEntity(sql, athleteId, "plan_version", id))
    ?.workouts as Row[];
  const completed =
    await sql`select distinct r.planned_workout_id from workout_results r join planned_workouts w on w.id=r.planned_workout_id join plan_versions p on p.id=w.plan_version_id where r.athlete_id=${athleteId} and r.deleted_at is null and p.training_block_id=${String(block.id)}`;
  for (const result of completed) {
    const historical = await readWorkoutPrescription(
      sql,
      String(result.planned_workout_id),
    );
    const current = after.find(
      (w) => w.logicalWorkoutId === historical.logicalWorkoutId,
    );
    // A device may upload against a superseded prescription after an offline
    // recording. Preserve that historical result and freeze the accepted head;
    // unrelated future edits must not rewrite or resurrect its logical session.
    const protectedPrescription = input.expectedActivePlanVersionId
      ? before.find((w) => w.logicalWorkoutId === historical.logicalWorkoutId)
      : historical;
    if (
      hash(semantic(current ?? null)) !==
      hash(semantic(protectedPrescription ?? null))
    )
      throw new ApiError(
        409,
        "COMPLETED_WORKOUT_IMMUTABLE",
        "This revision changes or removes a workout with recorded history.",
      );
  }
  if (input.proposalId) {
    const proposal = await owned(
      sql,
      "action_proposals",
      input.proposalId,
      athleteId,
    );
    if (
      !["pending", "accepted"].includes(String(proposal.status)) ||
      new Date(String(proposal.expires_at)) <= new Date() ||
      proposal.base_plan_version_id !== input.expectedActivePlanVersionId
    )
      throw new ApiError(
        409,
        "PROPOSAL_STALE",
        "The proposal is no longer applicable.",
      );
    const payload = proposal.action_payload as Row;
    if (
      proposal.action_type === "move_workout" &&
      !after.some(
        (w) =>
          w.logicalWorkoutId === payload.logicalWorkoutId &&
          w.scheduledDate === payload.targetDate,
      )
    )
      throw new ApiError(
        400,
        "PROPOSAL_MISMATCH",
        "The accepted plan does not contain the proposed move.",
      );
    if (proposal.action_type === "substitute_exercise") {
      const workout = after.find(
        (w) => w.logicalWorkoutId === payload.logicalWorkoutId,
      );
      const strength = workout?.strength as { exercises?: Row[] } | undefined;
      if (
        !strength?.exercises?.some(
          (e) => e.exerciseId === payload.replacementExerciseId,
        )
      )
        throw new ApiError(
          400,
          "PROPOSAL_MISMATCH",
          "The accepted plan does not contain the proposed substitution.",
        );
    }
    await updateRow(sql, "action_proposals", input.proposalId, {
      status: "applied",
      acceptedAt: new Date(),
      appliedPlanVersionId: id,
      revision: String(BigInt(String(proposal.revision)) + 1n),
      updatedAt: new Date(),
    });
    await emit(
      sql,
      athleteId,
      "action_proposal",
      input.proposalId,
      "upsert",
      String(BigInt(String(proposal.revision)) + 1n),
    );
  } else if (plan.origin === "coach" && authorization) {
    const [receipt] =
      await sql`select a.id from agent_actions a join agent_runs r on r.id=a.run_id where a.id=${authorization.actionId} and a.athlete_id=${athleteId} and a.receipt->>'planVersionId'=${id} and a.receipt->>'lifecycle'='applied' and r.api_version=2 and ((a.authorization->>'source'='run' and r.request->'mutation'->>'mode'='apply' and r.status='running') or (a.authorization->>'source'='draft_acceptance' and r.status='succeeded'))`;
    if (!receipt)
      throw new ApiError(
        403,
        "AGENT_AUTHORIZATION_REQUIRED",
        "A verified server action receipt is required.",
      );
  } else if (plan.origin === "coach")
    throw new ApiError(
      400,
      "PROPOSAL_REQUIRED",
      "A coach-origin plan must reference its accepted proposal.",
    );
  const changes = planDiff(before, after);
  const changeId = crypto.randomUUID();
  await insertRow(sql, "plan_change_sets", {
    id: changeId,
    athleteId,
    fromPlanVersionId: input.expectedActivePlanVersionId,
    toPlanVersionId: id,
    origin: plan.origin,
    reasonCode: input.reasonCode,
    explanation: input.explanation,
    material:
      changes.length > 1 || changes.some((c) => c.changeType !== "moved"),
    proposalId: input.proposalId,
    acceptedAt: new Date(),
  });
  for (const change of changes)
    await insertRow(sql, "plan_change_items", {
      ...change,
      changeSetId: changeId,
    });
  await emit(sql, athleteId, "plan_change_set", changeId, "upsert", null);
  if (input.expectedActivePlanVersionId) {
    const [old] =
      await sql`update plan_versions set status='superseded',revision=revision+1,updated_at=now() where id=${input.expectedActivePlanVersionId} returning revision::text`;
    await emit(
      sql,
      athleteId,
      "plan_version",
      input.expectedActivePlanVersionId,
      "upsert",
      String(old?.revision),
    );
  }
  const [head] =
    await sql`update training_blocks set active_plan_version_id=${id},status='active',revision=revision+1,updated_at=now() where id=${String(block.id)} returning revision::text`;
  await emit(
    sql,
    athleteId,
    "training_block",
    String(block.id),
    "upsert",
    String(head?.revision),
  );
  return updateRow(sql, "plan_versions", id, {
    status: "active",
    activatedAt: new Date(),
    revision: String(BigInt(String(plan.revision)) + 1n),
    updatedAt: new Date(),
  });
}
