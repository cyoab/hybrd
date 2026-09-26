import { ApiError } from "../api/errors";
import { type Query, type Row, wire } from "../db/store";
import { CanonicalSchemas } from "./records";

export const entityTables = {
  athlete: "athletes",
  athlete_details: "athlete_details",
  athlete_goal: "athlete_goals",
  training_preferences: "athlete_training_preferences",
  availability_rule: "athlete_availability_rules",
  availability_override: "athlete_availability_overrides",
  baseline_snapshot: "baseline_snapshots",
  planning_context_snapshot: "planning_context_snapshots",
  athlete_equipment: "athlete_equipment",
  exercise_preference: "athlete_exercise_preferences",
  training_block: "training_blocks",
  plan_version: "plan_versions",
  workout_result: "workout_results",
  activity_source_record: "activity_source_records",
  plan_change_set: "plan_change_sets",
  coach_thread: "coach_threads",
  coach_message: "coach_messages",
  action_proposal: "action_proposals",
  structured_decision: "structured_decisions",
  entitlement: "entitlements",
} as const;
export type EntityType = keyof typeof entityTables;
export async function children(
  sql: Query,
  table: string,
  column: string,
  id: string,
  order = "id",
) {
  return (
    await sql<
      Row[]
    >`select * from ${sql(table)} where ${sql(column)}=${id} order by ${sql(order)}`
  ).map((row) => {
    const result = wire(row);
    delete result[
      column.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase())
    ];
    return result;
  });
}
export async function readWorkoutPrescription(sql: Query, id: string) {
  const [raw] = await sql<Row[]>`select * from planned_workouts where id=${id}`;
  if (!raw) throw new ApiError(404, "NOT_FOUND", "Prescription unavailable.");
  const workout = wire(raw);
  delete workout.planVersionId;
  delete workout.createdAt;
  if (workout.discipline === "running") {
    const [run] = await children(
      sql,
      "run_prescriptions",
      "planned_workout_id",
      id,
      "planned_workout_id",
    );
    const blocks = await children(
      sql,
      "run_prescription_blocks",
      "planned_workout_id",
      id,
      "sequence",
    );
    for (const block of blocks)
      block.steps = await children(
        sql,
        "run_prescription_steps",
        "block_id",
        String(block.id),
        "sequence",
      );
    workout.run = { ...run, blocks };
  } else {
    const [strength] = await children(
      sql,
      "strength_prescriptions",
      "planned_workout_id",
      id,
      "planned_workout_id",
    );
    const exercises = await children(
      sql,
      "strength_exercise_prescriptions",
      "planned_workout_id",
      id,
      "sequence",
    );
    for (const exercise of exercises) {
      exercise.sets = await children(
        sql,
        "strength_set_prescriptions",
        "exercise_prescription_id",
        String(exercise.id),
        "set_number",
      );
      exercise.substitutions = (
        await children(
          sql,
          "strength_substitution_options",
          "exercise_prescription_id",
          String(exercise.id),
          "priority",
        )
      ).map((s) => ({
        exerciseId: s.substituteExerciseId,
        priority: s.priority,
        rationale: s.rationale,
      }));
    }
    workout.strength = { ...strength, exercises };
  }
  return workout;
}
export async function readEntity(
  sql: Query,
  athleteId: string,
  type: EntityType,
  id: string,
): Promise<Row | null> {
  const table = entityTables[type];
  const [raw] =
    type === "athlete"
      ? await sql<
          Row[]
        >`select * from athletes where id=${id} and id=${athleteId}`
      : await sql<
          Row[]
        >`select * from ${sql(table)} where id=${id} and athlete_id=${athleteId}`;
  if (!raw) return null;
  const row = wire(raw);
  if (raw.deleted_at) return row;
  if (type === "plan_version") {
    const ids =
      await sql`select id from planned_workouts where plan_version_id=${id} order by scheduled_date,id`;
    row.workouts = await Promise.all(
      ids.map((w) => readWorkoutPrescription(sql, String(w.id))),
    );
  }
  if (type === "workout_result") {
    if (row.discipline === "running") {
      const [run] = await children(
        sql,
        "run_results",
        "workout_result_id",
        id,
        "workout_result_id",
      );
      row.run = run
        ? {
            ...run,
            segments: await children(
              sql,
              "run_result_segments",
              "workout_result_id",
              id,
              "sequence",
            ),
          }
        : null;
    } else {
      const exercises = await children(
        sql,
        "strength_exercise_results",
        "workout_result_id",
        id,
        "sequence",
      );
      for (const exercise of exercises)
        exercise.sets = await children(
          sql,
          "strength_set_results",
          "exercise_result_id",
          String(exercise.id),
          "set_number",
        );
      row.exercises = exercises;
    }
  }
  if (type === "plan_change_set")
    row.items = await children(sql, "plan_change_items", "change_set_id", id);
  return CanonicalSchemas[type].parse(row) as Row;
}
