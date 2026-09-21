import { ApiError } from "../api/errors";
import { catalogReference, insertRow, type Tx } from "../db/store";
import { WorkoutInput } from "./schemas";

export async function writeWorkoutChildren(
  sql: Tx,
  athleteId: string,
  id: string,
  body: unknown,
) {
  const input = WorkoutInput.parse(body);
  if (input.plannedWorkoutId) {
    const [planned] =
      await sql`select w.* from planned_workouts w join plan_versions p on p.id=w.plan_version_id where w.id=${input.plannedWorkoutId} and p.athlete_id=${athleteId} and p.activated_at is not null`;
    if (
      !planned ||
      planned.discipline !== input.discipline ||
      planned.logical_workout_id !== input.logicalWorkoutId
    )
      throw new ApiError(
        400,
        "INVALID_PRESCRIPTION",
        "The result must reference an accepted prescription and its logical identity owned by this athlete.",
      );
  } else if (input.logicalWorkoutId)
    throw new ApiError(
      400,
      "INVALID_PRESCRIPTION",
      "A logical identity requires the exact prescription ID.",
    );
  await sql`delete from run_results where workout_result_id=${id}`;
  await sql`delete from strength_exercise_results where workout_result_id=${id}`;
  if (input.discipline === "running" && input.run) {
    const { segments, ...run } = input.run;
    await insertRow(sql, "run_results", { ...run, workoutResultId: id });
    for (const segment of segments) {
      if (segment.prescriptionStepId) {
        const [step] =
          await sql`select s.id,b.repeat_count from run_prescription_steps s join run_prescription_blocks b on b.id=s.block_id where s.id=${segment.prescriptionStepId} and b.planned_workout_id=${input.plannedWorkoutId}`;
        if (
          !step ||
          (segment.repeatIteration !== null &&
            segment.repeatIteration > Number(step.repeat_count))
        )
          throw new ApiError(
            400,
            "INVALID_PRESCRIPTION",
            "A segment references an unrelated step or repeat.",
          );
      }
      await insertRow(sql, "run_result_segments", {
        ...segment,
        workoutResultId: id,
      });
    }
  }
  if (input.discipline === "strength")
    for (const exercise of input.exercises) {
      await catalogReference(sql, "exercises", exercise.exerciseId);
      if (exercise.prescribedExerciseId) {
        const [prescribed] =
          await sql`select id from strength_exercise_prescriptions where id=${exercise.prescribedExerciseId} and planned_workout_id=${input.plannedWorkoutId}`;
        if (!prescribed)
          throw new ApiError(
            400,
            "INVALID_PRESCRIPTION",
            "An exercise references an unrelated prescription.",
          );
      }
      const { sets, ...data } = exercise;
      await insertRow(sql, "strength_exercise_results", {
        ...data,
        workoutResultId: id,
      });
      for (const set of sets) {
        if (set.prescribedSetId) {
          const [prescribed] =
            await sql`select id from strength_set_prescriptions where id=${set.prescribedSetId} and exercise_prescription_id=${exercise.prescribedExerciseId}`;
          if (!prescribed)
            throw new ApiError(
              400,
              "INVALID_PRESCRIPTION",
              "A set references an unrelated prescription.",
            );
        }
        await insertRow(sql, "strength_set_results", {
          ...set,
          exerciseResultId: exercise.id,
        });
      }
    }
}
