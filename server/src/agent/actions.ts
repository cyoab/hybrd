import type postgres from "postgres";
import {
  emit,
  hash,
  insertRow,
  owned,
  type Row,
  type Tx,
  wire,
} from "../db/store";
import { activatePlan, createPlan, planDiff, semantic } from "../plans/service";
import { evidence } from "./evidence";
import {
  assertScope,
  canonicalWorkouts,
  cloneWorkout,
  contextSnapshot,
  fail,
  manifestFor,
  planningState,
  type StagedPlan,
  validateWorkouts,
} from "./planning";
import { ActionReceipt, type RunInputV2, UndoInput } from "./v2-schemas";

async function persistPlan(
  sql: Tx,
  athlete: Row,
  run: Row,
  staged: StagedPlan,
  scope: NonNullable<RunInputV2["mutation"]>,
) {
  const athleteId = String(athlete.id),
    state = await planningState(sql, athlete),
    context = contextSnapshot(state),
    contextId = crypto.randomUUID(),
    blockId = scope.trainingBlockId ?? crypto.randomUUID(),
    planId = crypto.randomUUID(),
    actionId = crypto.randomUUID();
  if (!scope.trainingBlockId) {
    await insertRow(sql, "training_blocks", {
      id: blockId,
      athleteId,
      name: staged.name,
      startDate: scope.startDate,
      endDate: scope.endDate,
      phase: staged.phase,
      status: "draft",
    });
    await emit(sql, athleteId, "training_block", blockId, "upsert", "1");
  }
  await insertRow(sql, "planning_context_snapshots", {
    ...context,
    id: contextId,
    athleteId,
    checksum: `sha256:${hash(context.snapshot)}`,
  });
  await emit(
    sql,
    athleteId,
    "planning_context_snapshot",
    contextId,
    "upsert",
    null,
  );
  await createPlan(sql, athleteId, planId, {
    trainingBlockId: blockId,
    basePlanVersionId: scope.expectedActivePlanVersionId,
    planningContextSnapshotId: contextId,
    policyVersionId: context.policyVersionId,
    origin: "coach",
    summary: staged.rationale,
    workouts: staged.after,
  });
  const receipt = ActionReceipt.parse({
    id: actionId,
    runId: run.id,
    lifecycle: scope.mode === "apply" ? "applied" : "draft",
    trainingBlockId: blockId,
    planVersionId: planId,
    planRevision: scope.mode === "apply" ? "2" : "1",
    previousPlanVersionId: scope.expectedActivePlanVersionId,
    policyVersionId: context.policyVersionId,
    validationVersion: "agent-plan-validator-1",
    citations: evidence.filter((e) => staged.evidenceIds.includes(e.id)),
    changes: planDiff(staged.before, staged.after).map((c) => ({
      logicalWorkoutId: c.logicalWorkoutId,
      kind: c.changeType,
      beforePlannedWorkoutId: c.beforePlannedWorkoutId,
      afterPlannedWorkoutId: c.afterPlannedWorkoutId,
    })),
    changedLogicalWorkoutIds: staged.changed,
    rationale: staged.rationale,
    evidenceIds: staged.evidenceIds,
    validationIssues: staged.issues,
    compatibility: { executableVersion: 2, prescriptionSchemaVersion: 1 },
    syncRequired: true,
    undoAvailable: true,
    undoExpiresAt: new Date(Date.now() + 7 * 86400000).toISOString(),
    undoneByPlanVersionId: null,
    createdAt: new Date().toISOString(),
  });
  let preferenceBefore: unknown = null,
    preferenceAfter: unknown = null;
  if (staged.recurringPreference) {
    const p = staged.recurringPreference;
    const [prior] =
      await sql`select * from agent_exercise_rules where athlete_id=${athleteId} and from_exercise_id=${p.fromExerciseId}`;
    preferenceBefore = prior ? wire(prior) : null;
    const [saved] =
      await sql`insert into agent_exercise_rules(athlete_id,from_exercise_id,to_exercise_id,action_id) values(${athleteId},${p.fromExerciseId},${p.toExerciseId},${actionId}) on conflict(athlete_id,from_exercise_id) do update set to_exercise_id=excluded.to_exercise_id,action_id=excluded.action_id,revision=agent_exercise_rules.revision+1 returning *`;
    preferenceAfter = wire(saved!);
  }
  await insertRow(sql, "agent_actions", {
    id: actionId,
    athleteId,
    runId: run.id,
    receipt,
    before: staged.before,
    after: staged.after,
    preferenceBefore,
    preferenceAfter,
    authorization:
      scope.mode === "apply"
        ? { source: "run", requestHash: run.request_hash }
        : null,
  });
  if (scope.mode === "apply")
    await activatePlan(
      sql,
      athleteId,
      planId,
      {
        expectedActivePlanVersionId: scope.expectedActivePlanVersionId,
        accepted: true,
        reasonCode: "agent_explicit_request",
        explanation: staged.rationale,
        proposalId: null,
      },
      { actionId },
    );
  await emit(
    sql,
    athleteId,
    "plan_version",
    planId,
    "upsert",
    receipt.planRevision,
  );
  return receipt;
}
export async function commitPlan(
  sql: Tx,
  athlete: Row,
  run: Row,
  staged: StagedPlan,
  input: RunInputV2,
) {
  await assertScope(sql, athlete, input);
  // The caller wraps completion in a savepoint: receipts, preferences, plan activation,
  // sync events and the assistant message either all commit or none do.
  return persistPlan(sql, athlete, run, staged, input.mutation!);
}
export async function undoAction(
  sql: Tx,
  athlete: Row,
  id: string,
  key: string,
  body: unknown,
) {
  const input = UndoInput.parse(body),
    athleteId = String(athlete.id),
    action = await owned(sql, "agent_actions", id, athleteId),
    receipt = ActionReceipt.parse(action.receipt),
    fingerprint = hash(input);
  if (action.undo_key) {
    if (action.undo_key !== key || action.undo_hash !== fingerprint)
      fail(
        "UNDO_ALREADY_APPLIED",
        "This action has already been undone; restore its receipt.",
      );
    return receipt;
  }
  if (Date.parse(receipt.undoExpiresAt) <= Date.now())
    fail("UNDO_EXPIRED", "This action's seven-day undo window has expired.");
  if (
    receipt.changedLogicalWorkoutIds.some((id) =>
      input.protectedLogicalWorkoutIds.includes(id),
    )
  )
    fail("WORKOUT_PROTECTED", "An active recording pins an affected workout.");
  const state = await planningState(sql, athlete);
  if (state.contextToken !== input.contextToken)
    fail("AGENT_CONTEXT_CHANGED", "Refresh planning context before undoing.");
  const manifest = await manifestFor(sql, athleteId, input.deviceId);
  const block = await owned(
    sql,
    "training_blocks",
    receipt.trainingBlockId,
    athleteId,
  );
  if (block.active_plan_version_id !== input.expectedActivePlanVersionId)
    fail("PLAN_HEAD_CONFLICT", "Refresh the active plan before undoing.");
  if (action.preference_after) {
    const after = action.preference_after as Row;
    const [current] =
      await sql`select * from agent_exercise_rules where athlete_id=${athleteId} and from_exercise_id=${String(after.fromExerciseId)}`;
    if (!current || hash(wire(current)) !== hash(after))
      fail(
        "UNDO_PREFERENCE_CONFLICT",
        "This exercise preference has changed since the action.",
      );
  }
  if (receipt.lifecycle === "draft") {
    const plan = await owned(
      sql,
      "plan_versions",
      receipt.planVersionId,
      athleteId,
    );
    if (plan.status !== "draft")
      fail(
        "UNDO_PLAN_CONFLICT",
        "The draft has since been activated or changed.",
      );
    // Keep the immutable draft for audit and mark it rejected.
    await sql`update plan_versions set status='rejected',revision=revision+1,updated_at=now() where id=${receipt.planVersionId}`;
    await emit(
      sql,
      athleteId,
      "plan_version",
      receipt.planVersionId,
      "upsert",
      String(BigInt(String(plan.revision)) + 1n),
    );
  } else {
    if (!input.expectedActivePlanVersionId)
      fail("PLAN_HEAD_CONFLICT", "An active plan is required.");
    const current = await canonicalWorkouts(
        sql,
        athleteId,
        input.expectedActivePlanVersionId,
      ),
      before = action.before as StagedPlan["before"],
      after = action.after as StagedPlan["after"];
    for (const logical of receipt.changedLogicalWorkoutIds) {
      const a = after.find((w) => w.logicalWorkoutId === logical),
        c = current.find((w) => w.logicalWorkoutId === logical);
      if (hash(semantic(a ?? null)) !== hash(semantic(c ?? null)))
        fail(
          "UNDO_PLAN_CONFLICT",
          "A workout changed after this action. Undo would overwrite a later edit.",
        );
    }
    const restored = current
      .filter(
        (w) => !receipt.changedLogicalWorkoutIds.includes(w.logicalWorkoutId),
      )
      .concat(
        before.filter((w) =>
          receipt.changedLogicalWorkoutIds.includes(w.logicalWorkoutId),
        ),
      )
      .map(cloneWorkout);
    // Undo of creation can leave zero sessions: close only the newly created, otherwise unchanged block.
    if (!restored.length) {
      const [recorded] =
        await sql`select r.id from workout_results r join planned_workouts w on w.id=r.planned_workout_id where r.athlete_id=${athleteId} and r.deleted_at is null and w.plan_version_id in (select id from plan_versions where training_block_id=${receipt.trainingBlockId}) limit 1`;
      if (recorded)
        fail(
          "COMPLETED_WORKOUT_IMMUTABLE",
          "A recorded plan cannot be removed by Undo.",
        );
      await sql`update training_blocks set status='cancelled',active_plan_version_id=null,revision=revision+1,updated_at=now() where id=${receipt.trainingBlockId}`;
      await sql`update plan_versions set status='superseded',revision=revision+1,updated_at=now() where id=${input.expectedActivePlanVersionId}`;
      await emit(
        sql,
        athleteId,
        "training_block",
        receipt.trainingBlockId,
        "upsert",
        String(BigInt(String(block.revision)) + 1n),
      );
      const plan = await owned(
        sql,
        "plan_versions",
        input.expectedActivePlanVersionId,
        athleteId,
      );
      await emit(
        sql,
        athleteId,
        "plan_version",
        String(plan.id),
        "upsert",
        String(plan.revision),
      );
    } else {
      await validateWorkouts(
        sql,
        athlete,
        restored.filter((w) =>
          receipt.changedLogicalWorkoutIds.includes(w.logicalWorkoutId),
        ),
        state,
        manifest,
        restored,
      );
      const context = contextSnapshot(state),
        contextId = crypto.randomUUID(),
        planId = crypto.randomUUID();
      await insertRow(sql, "planning_context_snapshots", {
        ...context,
        id: contextId,
        athleteId,
        checksum: `sha256:${hash(context.snapshot)}`,
      });
      await emit(
        sql,
        athleteId,
        "planning_context_snapshot",
        contextId,
        "upsert",
        null,
      );
      await createPlan(sql, athleteId, planId, {
        trainingBlockId: receipt.trainingBlockId,
        basePlanVersionId: input.expectedActivePlanVersionId,
        planningContextSnapshotId: contextId,
        policyVersionId: context.policyVersionId,
        origin: "manual_edit",
        summary: `Undo: ${receipt.rationale}`,
        workouts: restored,
      });
      await activatePlan(sql, athleteId, planId, {
        expectedActivePlanVersionId: input.expectedActivePlanVersionId,
        accepted: true,
        reasonCode: "agent_action_undo",
        explanation: `Undo action ${id}`,
        proposalId: null,
      });
      await emit(sql, athleteId, "plan_version", planId, "upsert", "2");
      receipt.undoneByPlanVersionId = planId;
    }
  }
  if (action.preference_after) {
    const p = action.preference_after as Row,
      b = action.preference_before as Row | null;
    if (b)
      await sql`update agent_exercise_rules set to_exercise_id=${String(b.toExerciseId)},action_id=${String(b.actionId)},revision=revision+1 where athlete_id=${athleteId} and from_exercise_id=${String(p.fromExerciseId)}`;
    else
      await sql`delete from agent_exercise_rules where athlete_id=${athleteId} and from_exercise_id=${String(p.fromExerciseId)}`;
  }
  receipt.lifecycle = "undone";
  receipt.undoAvailable = false;
  await sql`update agent_actions set receipt=${sql.json(receipt as unknown as postgres.JSONValue)},undo_key=${key},undo_hash=${fingerprint} where id=${id}`;
  return receipt;
}

export async function applyDraft(
  sql: Tx,
  athlete: Row,
  id: string,
  key: string,
  body: unknown,
) {
  const input = UndoInput.parse(body),
    athleteId = String(athlete.id),
    action = await owned(sql, "agent_actions", id, athleteId),
    receipt = ActionReceipt.parse(action.receipt),
    fingerprint = hash(input);
  if (action.apply_key) {
    if (action.apply_key !== key || action.apply_hash !== fingerprint)
      fail("ACTION_ALREADY_APPLIED", "Restore this action's existing receipt.");
    return receipt;
  }
  if (receipt.lifecycle !== "draft")
    fail("ACTION_NOT_DRAFT", "Only a validated draft can be applied.");
  if (Date.parse(receipt.undoExpiresAt) <= Date.now())
    fail("ACTION_EXPIRED", "Generate a fresh draft after seven days.");
  if (
    receipt.changedLogicalWorkoutIds.some((id) =>
      input.protectedLogicalWorkoutIds.includes(id),
    )
  )
    fail("WORKOUT_PROTECTED", "An active recording pins an affected workout.");
  const state = await planningState(sql, athlete);
  if (state.contextToken !== input.contextToken)
    fail(
      "AGENT_CONTEXT_CHANGED",
      "Sync and refresh context before applying a draft.",
    );
  const block = await owned(
    sql,
    "training_blocks",
    receipt.trainingBlockId,
    athleteId,
  );
  if (
    block.active_plan_version_id !== input.expectedActivePlanVersionId ||
    receipt.previousPlanVersionId !== input.expectedActivePlanVersionId
  )
    fail(
      "PLAN_HEAD_CONFLICT",
      "The active plan changed; generate a new draft.",
    );
  const workouts = await canonicalWorkouts(
    sql,
    athleteId,
    receipt.planVersionId,
  );
  await validateWorkouts(
    sql,
    athlete,
    workouts.filter((w) =>
      receipt.changedLogicalWorkoutIds.includes(w.logicalWorkoutId),
    ),
    state,
    await manifestFor(sql, athleteId, input.deviceId),
    workouts,
  );
  receipt.lifecycle = "applied";
  receipt.planRevision = "2";
  await sql`update agent_actions set receipt=${sql.json(receipt)},apply_key=${key},apply_hash=${fingerprint},"authorization"=${sql.json({ source: "draft_acceptance", contextToken: input.contextToken, deviceId: input.deviceId })} where id=${id}`;
  await activatePlan(
    sql,
    athleteId,
    receipt.planVersionId,
    {
      expectedActivePlanVersionId: input.expectedActivePlanVersionId,
      accepted: true,
      reasonCode: "agent_draft_acceptance",
      explanation: receipt.rationale,
      proposalId: null,
    },
    { actionId: id },
  );
  await emit(
    sql,
    athleteId,
    "plan_version",
    receipt.planVersionId,
    "upsert",
    "2",
  );
  return receipt;
}
