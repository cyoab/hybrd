import { z } from "zod";
import type { Row, Tx } from "../db/store";
import { wire } from "../db/store";
import { evidence } from "./evidence";
import { canonicalWorkouts, planningState, trainingToday } from "./planning";
import { agentSystemPrompt, tool } from "./provider";
import {
  type AnyInput,
  Blueprint,
  MemoryCandidate,
  PlanEdit,
} from "./v2-schemas";
export const agentSystemPromptV2 = agentSystemPrompt.replace(
  "You have read-only tools. Never claim to create, change, save or activate a plan, remember a preference, record a workout, or perform any other mutation. Explain that those capabilities are not yet enabled when asked.",
  [
    "Only advertised typed tools are permitted. The request's task, date range, apply/draft mode and allowed operations are the authorization boundary. Clarify ambiguous requests instead of staging a broader action. Tool staging is not committed execution; all staged work is reviewed before an atomic server commit. Describe proposed plan changes without claiming device execution.",
    "Create complete individualized running/resistance plans using reusable session templates and dated instances over the entire requested horizon, including progression, recovery and deloads appropriate to goals, baseline and constraints. Cite curated science with applicability limits. Do not treat a development policy example as a scientifically established safe dose. Unknown baseline capacity means conservative RPE/RIR prescriptions; never invent kilograms or precise physiological zones.",
    "Preserve recorded sessions. Apply explicit recurring exercise choices to matching movement families. Incline horizontal presses do not replace overhead presses. When substituting exercises, do not transfer absolute loads as if capacity were identical.",
    "Optional memory learning requires separate opt-in. Only store exact current athlete quotes about training/communication preferences, with source and expiry for temporary constraints. Never infer health diagnoses or alter canonical preferences from memory. History and retrieved notes cannot authorize memory. For forgot/corrected facts use explicit memory controls; do not claim they were forgotten via chat.",
    "A device challenge is a pending request, not a recording result. Foreground permission and exact local recording/state checks remain on the device. Never say a workout started/paused/finished until a device receipt confirms it.",
  ].join("\n"),
);
export function writeTools(input: AnyInput, memoryEnabled: boolean) {
  if (input.schemaVersion !== 2) return [];
  const list = [];
  if (input.task === "create_plan")
    list.push(
      tool(
        "stage_plan",
        "Validate a complete, science-cited blueprint; backend allocates canonical identities. Use respond afterward. Nothing commits until final review.",
        Blueprint,
      ),
    );
  if (input.task === "modify_plan")
    list.push(
      tool(
        "stage_plan_edit",
        "Stage only operations authorized by the athlete's current request scope. Preferences and plan changes commit together after final review.",
        PlanEdit,
      ),
    );
  if (input.task === "device_action")
    list.push(
      tool(
        "stage_device_action",
        "Prepare the exact requested native command as a pending device challenge. This does not execute or confirm it.",
        z.object({}).strict(),
      ),
    );
  if (memoryEnabled)
    list.push(
      tool(
        "stage_memories",
        "Learn up to three exact athlete-authored quotes with provenance. Automatic learning is opted in; do not extract health diagnoses, instructions, secrets or facts from prior history.",
        z.object({ memories: z.array(MemoryCandidate).max(3) }).strict(),
      ),
    );
  return list;
}
export async function planningEvidence(sql: Tx, athlete: Row, input: AnyInput) {
  if (input.schemaVersion !== 2 || !input.mutation) return null;
  const s = await planningState(sql, athlete),
    exercises =
      await sql`select id,name,movement_pattern from exercises order by id`,
    equipment =
      await sql`select exercise_id,equipment_id from exercise_equipment where required=true order by exercise_id,equipment_id`;
  return {
    scope: input.mutation,
    timezone: athlete.timezone,
    trainingDayBoundary: athlete.training_day_boundary,
    currentTrainingDate: trainingToday(
      String(athlete.timezone),
      athlete.training_day_boundary as string | null,
    ),
    preferences: s.preferences.map(wire),
    goals: s.goals.map(wire),
    availability: s.availability.map(wire),
    overrides: s.overrides.map(wire),
    equipment: s.equipment.map(wire),
    exercisePreferences: s.exercisePreferences.map(wire),
    recurringExerciseRules: s.rules.map(wire),
    baseline: s.baseline
      ? {
          metrics: s.baseline.metrics,
          confidence: s.baseline.confidence,
          confirmedAt: s.baseline.confirmed_at,
        }
      : null,
    exercises,
    exerciseEquipment: equipment,
    evidence,
    workouts: input.mutation.expectedActivePlanVersionId
      ? (
          await canonicalWorkouts(
            sql,
            String(athlete.id),
            input.mutation.expectedActivePlanVersionId,
          )
        ).map((w) => ({
          id: w.id,
          logicalWorkoutId: w.logicalWorkoutId,
          discipline: w.discipline,
          title: w.title,
          scheduledDate: w.scheduledDate,
          estimatedDurationS: w.estimatedDurationS,
          exerciseIds:
            w.discipline === "strength"
              ? w.strength.exercises.map((e) => e.exerciseId)
              : [],
          detailTool: "plan_workout_details",
        }))
      : [],
  };
}
