import type { z } from "zod";
import { ApiError } from "../api/errors";
import {
  AvailabilityOverrideInput,
  AvailabilityRuleInput,
  GoalInput,
  PlanningContextInput,
  PreferencesInput,
} from "../athlete/schemas";
import { hash, type Row, type Tx, wire } from "../db/store";
import { readEntity } from "../domain/read";
import { PlannedWorkoutInput } from "../plans/schemas";
import { semantic } from "../plans/service";
import { evidence } from "./evidence";
import {
  Blueprint,
  DeviceManifest,
  PlanEdit,
  type RunInputV2,
  type Template,
  type Workout,
} from "./v2-schemas";

export function fail(code: string, message: string): never {
  throw new ApiError(409, code, message);
}
function fields<S extends z.ZodRawShape>(schema: z.ZodObject<S>, row: Row) {
  const w = wire(row);
  return schema.parse(
    Object.fromEntries(
      Object.keys(schema.shape)
        .filter((k) => w[k] !== undefined)
        .map((k) => [k, w[k]]),
    ),
  );
}
export async function planningState(sql: Tx, athlete: Row) {
  const id = String(athlete.id);
  const goals = await sql<
    Row[]
  >`select * from athlete_goals where athlete_id=${id} and deleted_at is null order by id`;
  const preferences = await sql<
    Row[]
  >`select * from athlete_training_preferences where athlete_id=${id} and deleted_at is null`;
  const availability = await sql<
    Row[]
  >`select * from athlete_availability_rules where athlete_id=${id} and deleted_at is null order by id`;
  const overrides = await sql<
    Row[]
  >`select * from athlete_availability_overrides where athlete_id=${id} and deleted_at is null order by id`;
  const equipment = await sql<
    Row[]
  >`select * from athlete_equipment where athlete_id=${id} and deleted_at is null order by id`;
  const exercisePreferences = await sql<
    Row[]
  >`select * from athlete_exercise_preferences where athlete_id=${id} and deleted_at is null order by id`;
  const rules = await sql<
    Row[]
  >`select * from agent_exercise_rules where athlete_id=${id} order by from_exercise_id`;
  const blocks = await sql<
    Row[]
  >`select * from training_blocks where athlete_id=${id} and deleted_at is null order by id`;
  const results = await sql<
    Row[]
  >`select id,revision::text,planned_workout_id,training_date from workout_results where athlete_id=${id} and deleted_at is null order by id`;
  const [baseline] = await sql<
    Row[]
  >`select * from baseline_snapshots where athlete_id=${id} and deleted_at is null order by created_at desc,id desc limit 1`;
  const [details] = await sql<
    Row[]
  >`select * from athlete_details where athlete_id=${id} and deleted_at is null`;
  const [policy] = await sql<
    Row[]
  >`select * from training_policy_versions where status='published' order by version desc limit 1`;
  const state = {
    profileRevision: String(athlete.revision),
    timezone: athlete.timezone,
    trainingDayBoundary: athlete.training_day_boundary,
    goals,
    preferences,
    availability,
    overrides,
    equipment,
    exercisePreferences,
    rules,
    blocks,
    results,
    baseline: baseline ?? null,
    details: details ?? null,
    policy: policy ?? null,
  };
  return { ...state, contextToken: hash(state) };
}
export function trainingToday(
  timezone: string,
  boundary: string | null,
  now = new Date(),
) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);
  const p = Object.fromEntries(parts.map((x) => [x.type, x.value]));
  const day = `${p.year}-${p.month}-${p.day}`,
    time = `${p.hour}:${p.minute}:${p.second}`;
  return boundary && time < boundary
    ? new Date(Date.parse(`${day}T12:00:00Z`) - 86400000)
        .toISOString()
        .slice(0, 10)
    : day;
}
export async function assertScope(sql: Tx, athlete: Row, input: RunInputV2) {
  const scope = input.mutation;
  if (!scope) fail("AGENT_SCOPE_REQUIRED", "Select a plan operation scope.");
  const state = await planningState(sql, athlete);
  if (
    state.contextToken !== scope.contextToken ||
    state.profileRevision !== scope.expectedProfileRevision
  )
    fail(
      "AGENT_CONTEXT_CHANGED",
      "Sync and refresh planning context before trying again.",
    );
  if (scope.trainingBlockId) {
    const block = state.blocks.find((b) => b.id === scope.trainingBlockId);
    if (
      !block ||
      block.active_plan_version_id !== scope.expectedActivePlanVersionId
    )
      fail("PLAN_HEAD_CONFLICT", "The selected active plan changed.");
    if (
      scope.startDate < String(wire(block).startDate) ||
      scope.endDate > String(wire(block).endDate)
    )
      fail("OUTSIDE_BLOCK", "Edit scope must stay within the selected block.");
  }
  const localToday = trainingToday(
    String(athlete.timezone),
    athlete.training_day_boundary as string | null,
  );
  if (scope.startDate < localToday)
    fail(
      "AGENT_PAST_SCOPE",
      "Only today and future training days may be changed.",
    );
  await manifestFor(sql, String(athlete.id), input.deviceId);
  return state;
}
export async function manifestFor(
  sql: Tx,
  athleteId: string,
  deviceId: string,
) {
  const [row] =
    await sql`select m.manifest from agent_device_manifests m join device_installations d on d.id=m.device_id where m.athlete_id=${athleteId} and m.device_id=${deviceId} and d.athlete_id=${athleteId} and d.revoked_at is null and m.updated_at>now()-interval '24 hours'`;
  if (!row)
    fail(
      "DEVICE_CAPABILITIES_REQUIRED",
      "Refresh this device's capability manifest before using agent actions.",
    );
  return DeviceManifest.parse(row.manifest);
}
export function expandTemplate(
  template: Template,
  date: string,
  timezone: string,
  logicalWorkoutId: string = crypto.randomUUID(),
): Workout {
  const { key: _key, ...t } = template;
  const base = {
    ...t,
    id: crypto.randomUUID(),
    logicalWorkoutId,
    scheduledDate: date,
    scheduledStartAt: null,
    timezone,
    plannedDistanceM: null,
  };
  if (template.discipline === "running")
    return PlannedWorkoutInput.parse({
      ...base,
      run: {
        ...template.run,
        blocks: template.run.blocks.map((b, sequence) => ({
          ...b,
          id: crypto.randomUUID(),
          sequence,
          steps: b.steps.map((s, sequence) => ({
            ...s,
            id: crypto.randomUUID(),
            sequence,
          })),
        })),
      },
    });
  const groups = new Map<string, string>();
  return PlannedWorkoutInput.parse({
    ...base,
    strength: {
      ...template.strength,
      exercises: template.strength.exercises.map((e, sequence) => {
        const { supersetKey, ...rest } = e;
        if (supersetKey && !groups.has(supersetKey))
          groups.set(supersetKey, crypto.randomUUID());
        return {
          ...rest,
          id: crypto.randomUUID(),
          sequence,
          supersetGroupId: supersetKey ? groups.get(supersetKey) : null,
          sets: e.sets.map((s, i) => ({
            ...s,
            id: crypto.randomUUID(),
            setNumber: i + 1,
          })),
        };
      }),
    },
  });
}
export function cloneWorkout(workout: Workout): Workout {
  const w = structuredClone(workout);
  w.id = crypto.randomUUID();
  if (w.discipline === "running")
    for (const b of w.run.blocks) {
      b.id = crypto.randomUUID();
      for (const s of b.steps) s.id = crypto.randomUUID();
    }
  else
    for (const e of w.strength.exercises) {
      e.id = crypto.randomUUID();
      for (const s of e.sets) s.id = crypto.randomUUID();
    }
  return w;
}
export function cleanWorkout(row: Row): Workout {
  // Canonical read models include database parent/timestamp fields. Strip only those, never execution targets.
  const clean = (v: unknown): unknown =>
    Array.isArray(v)
      ? v.map(clean)
      : v && typeof v === "object"
        ? Object.fromEntries(
            Object.entries(v)
              .filter(
                ([k]) =>
                  ![
                    "createdAt",
                    "planVersionId",
                    "plannedWorkoutId",
                    "blockId",
                    "exercisePrescriptionId",
                  ].includes(k),
              )
              .map(([k, x]) => [k, clean(x)]),
          )
        : v;
  return PlannedWorkoutInput.parse(clean(row));
}
export async function canonicalWorkouts(
  sql: Tx,
  athleteId: string,
  planId: string,
) {
  const plan = await readEntity(sql, athleteId, "plan_version", planId);
  if (!plan) fail("REFERENCE_UNAVAILABLE", "Plan unavailable.");
  return (plan.workouts as Row[]).map(cleanWorkout);
}
export type StagedPlan = {
  name: string;
  phase: string;
  rationale: string;
  evidenceIds: string[];
  before: Workout[];
  after: Workout[];
  changed: string[];
  recurringPreference: { fromExerciseId: string; toExerciseId: string } | null;
  issues: { code: string; message: string }[];
};
export async function stagePlan(
  sql: Tx,
  athlete: Row,
  input: RunInputV2,
  args: unknown,
): Promise<StagedPlan> {
  const state = await assertScope(sql, athlete, input),
    scope = input.mutation!;
  let after: Workout[],
    before: Workout[] = [],
    name = "Training plan",
    phase = "build",
    rationale: string,
    ids: string[],
    recurringPreference: StagedPlan["recurringPreference"] = null;
  if (input.task === "create_plan") {
    const b = Blueprint.parse(args);
    name = b.name;
    phase = b.phase;
    rationale = b.rationale;
    ids = b.evidenceIds;
    const templates = new Map(b.templates.map((t) => [t.key, t]));
    if (templates.size !== b.templates.length)
      fail("BLUEPRINT_DUPLICATE_TEMPLATE", "Template keys must be unique.");
    after = b.sessions.map((s) => {
      const t = templates.get(s.templateKey);
      if (!t)
        fail(
          "BLUEPRINT_UNKNOWN_TEMPLATE",
          "Each dated session must reference a template.",
        );
      return expandTemplate(t, s.date, String(athlete.timezone));
    });
    const dates = [...new Set(after.map((w) => w.scheduledDate))].sort();
    const span = [scope.startDate, ...dates, scope.endDate];
    if (
      span.some(
        (d, i) =>
          i > 0 && Date.parse(d) - Date.parse(span[i - 1]!) > 7 * 86400000,
      )
    )
      fail(
        "BLUEPRINT_INCOMPLETE_HORIZON",
        "Specify sessions for the complete requested horizon, including later weeks.",
      );
  } else {
    const edit = PlanEdit.parse(args);
    rationale = edit.rationale;
    ids = edit.evidenceIds;
    recurringPreference = edit.recurringPreference;
    before = await canonicalWorkouts(
      sql,
      String(athlete.id),
      scope.expectedActivePlanVersionId!,
    );
    after = before.map(cloneWorkout);
    const block = state.blocks.find((b) => b.id === scope.trainingBlockId)!;
    name = String(block.name);
    phase = String(block.phase);
    for (const op of edit.operations) {
      if (!scope.operations.includes(op.kind))
        fail(
          "AGENT_OPERATION_OUT_OF_SCOPE",
          "This operation was not authorized by the requesting client.",
        );
      if (op.kind === "add") {
        after.push(
          expandTemplate(op.template, op.date, String(athlete.timezone)),
        );
        continue;
      }
      const w = after.find((w) => w.logicalWorkoutId === op.logicalWorkoutId);
      if (!w)
        fail(
          "REFERENCE_UNAVAILABLE",
          "The requested workout is absent from the current plan.",
        );
      if (
        w.scheduledDate < scope.startDate ||
        w.scheduledDate > scope.endDate ||
        scope.protectedLogicalWorkoutIds.includes(w.logicalWorkoutId)
      )
        fail(
          "WORKOUT_PROTECTED",
          "This workout is outside the editable scope or pinned by an active recording.",
        );
      if (op.kind === "move") {
        w.scheduledDate = op.date;
        w.scheduledStartAt = null;
      }
      if (op.kind === "remove") after = after.filter((x) => x !== w);
      if (op.kind === "replace_workout") {
        if (op.template.discipline !== w.discipline)
          fail(
            "DISCIPLINE_CONFLICT",
            "A logical workout cannot change discipline.",
          );
        after[after.indexOf(w)] = expandTemplate(
          op.template,
          w.scheduledDate,
          w.timezone,
          w.logicalWorkoutId,
        );
      }
      if (op.kind === "replace_exercise") {
        if (w.discipline !== "strength")
          fail("DISCIPLINE_CONFLICT", "Select a strength workout.");
        await compatibleExercise(sql, op.fromExerciseId, op.toExerciseId);
        const es = w.strength.exercises.filter(
          (e) => e.exerciseId === op.fromExerciseId,
        );
        if (!es.length)
          fail(
            "REFERENCE_UNAVAILABLE",
            "The exercise is absent from the selected workout.",
          );
        for (const e of es) {
          e.exerciseId = op.toExerciseId;
          e.substitutions = [];
          for (const s of e.sets) {
            s.loadKg = null;
            s.loadPercentE1rm = null;
            s.rirMin ??= 2;
            s.rirMax ??= 3;
          }
        }
      }
    }
    if (recurringPreference) {
      if (!scope.allowRecurringPreference || scope.mode !== "apply")
        fail(
          "PREFERENCE_NOT_AUTHORIZED",
          "Recurring preferences require explicit authorization in apply mode.",
        );
      await compatibleExercise(
        sql,
        recurringPreference.fromExerciseId,
        recurringPreference.toExerciseId,
      );
    }
  }
  if (ids.some((id) => !evidence.some((e) => e.id === id)))
    fail("AGENT_UNGROUNDED_RESPONSE", "Use published evidence IDs.");
  // Explicit exercise rules are deterministic constraints, never inferred from memory.
  const rules = state.rules.map((r) => ({
    fromExerciseId: String(r.from_exercise_id),
    toExerciseId: String(r.to_exercise_id),
  }));
  if (recurringPreference) {
    const i = rules.findIndex(
      (r) => r.fromExerciseId === recurringPreference!.fromExerciseId,
    );
    if (i >= 0) rules.splice(i, 1);
    rules.push(recurringPreference);
  }
  const recordedIds = state.results.map((r) => String(r.planned_workout_id));
  const protectedRows = recordedIds.length
    ? await sql`select logical_workout_id from planned_workouts where id in ${sql(recordedIds)}`
    : [];
  for (const w of after) {
    if (
      w.discipline !== "strength" ||
      w.scheduledDate < scope.startDate ||
      w.scheduledDate > scope.endDate ||
      scope.protectedLogicalWorkoutIds.includes(w.logicalWorkoutId) ||
      protectedRows.some((r) => r.logical_workout_id === w.logicalWorkoutId)
    )
      continue;
    // Existing rules do not broaden a one-off edit to otherwise untouched sessions.
    if (
      input.task !== "create_plan" &&
      !recurringPreference &&
      before.some(
        (b) =>
          b.logicalWorkoutId === w.logicalWorkoutId &&
          hash(semantic(b)) === hash(semantic(w)),
      )
    )
      continue;
    for (const e of w.strength.exercises) {
      const rule = rules.find((r) => r.fromExerciseId === e.exerciseId);
      if (rule) {
        e.exerciseId = rule.toExerciseId;
        e.substitutions = [];
        for (const s of e.sets) {
          s.loadKg = null;
          s.loadPercentE1rm = null;
          s.rirMin ??= 2;
          s.rirMax ??= 3;
        }
      }
    }
  }
  const old = new Map(before.map((w) => [w.logicalWorkoutId, w]));
  const changed = after
    .filter(
      (w) =>
        !old.has(w.logicalWorkoutId) ||
        hash(semantic(w)) !== hash(semantic(old.get(w.logicalWorkoutId))),
    )
    .map((w) => w.logicalWorkoutId);
  changed.push(
    ...before
      .filter(
        (w) => !after.some((a) => a.logicalWorkoutId === w.logicalWorkoutId),
      )
      .map((w) => w.logicalWorkoutId),
  );
  if (!changed.length)
    fail("AGENT_NO_CHANGES", "The proposed operation makes no changes.");
  for (const id of changed) {
    const a = after.find((w) => w.logicalWorkoutId === id);
    if (
      a &&
      (a.scheduledDate < scope.startDate || a.scheduledDate > scope.endDate)
    )
      fail(
        "OUTSIDE_SCOPE",
        "A changed workout falls outside the authorized date range.",
      );
  }
  if (
    changed.some(
      (id) =>
        scope.protectedLogicalWorkoutIds.includes(id) ||
        protectedRows.some((r) => r.logical_workout_id === id),
    )
  )
    fail(
      "COMPLETED_WORKOUT_IMMUTABLE",
      "An active or recorded workout cannot be changed or removed.",
    );
  const issues = await validateWorkouts(
    sql,
    athlete,
    after.filter((w) => changed.includes(w.logicalWorkoutId)),
    state,
    await manifestFor(sql, String(athlete.id), input.deviceId),
    after,
  );
  return {
    name,
    phase,
    rationale,
    evidenceIds: ids,
    before,
    after,
    changed,
    recurringPreference,
    issues,
  };
}
async function compatibleExercise(sql: Tx, from: string, to: string) {
  const rows =
    await sql`select id,movement_pattern from exercises where id in (${from},${to})`;
  if (
    from === to ||
    rows.length !== 2 ||
    rows[0]?.movement_pattern !== rows[1]?.movement_pattern
  )
    fail(
      "EXERCISE_SUBSTITUTION_INCOMPATIBLE",
      "Substitutions must use distinct catalog exercises in the same movement family.",
    );
}
export async function validateWorkouts(
  sql: Tx,
  athlete: Row,
  changed: Workout[],
  state: Awaited<ReturnType<typeof planningState>>,
  manifest: z.infer<typeof DeviceManifest>,
  all: Workout[],
) {
  const issues = [
    {
      code: "COACHING_LIMITS",
      message:
        "Training doses are individualized coaching estimates, not guarantees of safety. Evidence applicability and recorded baseline remain limitations.",
    },
  ];
  if (!state.preferences.length || state.availability.length !== 7)
    fail(
      "PLANNING_PROFILE_INCOMPLETE",
      "Complete training preferences and all seven availability days before creating or modifying a plan.",
    );
  const protectedIds = new Set(
    state.results.map((r) => String(r.planned_workout_id)),
  );
  const protectedLogical =
    await sql`select distinct logical_workout_id from planned_workouts where id in ${sql([...protectedIds].length ? [...protectedIds] : ["00000000-0000-0000-0000-000000000000"])} `;
  for (const w of changed) {
    if (
      protectedLogical.some((r) => r.logical_workout_id === w.logicalWorkoutId)
    )
      fail(
        "COMPLETED_WORKOUT_IMMUTABLE",
        "Recorded workouts cannot be changed.",
      );
    const rule = state.availability.find(
      (r) =>
        Number(r.day_of_week) ===
        new Date(`${w.scheduledDate}T12:00:00Z`).getUTCDay() + 1,
    );
    const override = state.overrides.find(
      (r) => String(wire(r).date) === w.scheduledDate,
    );
    const available = override?.available ?? rule?.available,
      maxSessions = override?.max_sessions ?? rule?.max_sessions ?? 0,
      maxMinutes = override?.max_session_minutes ?? rule?.max_session_minutes;
    if (
      !available ||
      all.filter((a) => a.scheduledDate === w.scheduledDate).length >
        Number(maxSessions)
    )
      fail(
        "AVAILABILITY_CONFLICT",
        "A session exceeds the athlete's daily availability.",
      );
    if (
      !w.estimatedDurationS ||
      (maxMinutes != null && w.estimatedDurationS > Number(maxMinutes) * 60)
    )
      fail(
        "SESSION_DURATION_CONFLICT",
        "Provide a duration within the athlete's available session time.",
      );
    if (w.discipline === "running") {
      const expanded = w.run.blocks.reduce(
        (n, b) => n + b.repeatCount * b.steps.length,
        0,
      );
      if (
        expanded >
        Math.min(manifest.maxExpandedSteps, manifest.maxResultSegments)
      )
        fail(
          "DEVICE_EXECUTION_LIMIT",
          "Expanded intervals exceed this device's execution/result limits.",
        );
      let minimumDuration = 0;
      for (const b of w.run.blocks)
        for (const s of b.steps) {
          if (Boolean(s.durationS) === Boolean(s.distanceM))
            fail(
              "UNSUPPORTED_COMPLETION",
              "Use exactly one positive duration or distance end condition.",
            );
          if (
            !manifest.completion.includes(s.durationS ? "duration" : "distance")
          )
            fail(
              "UNSUPPORTED_COMPLETION",
              "This device does not support the end condition.",
            );
          if (s.durationS) minimumDuration += s.durationS * b.repeatCount;
          else if (s.distanceM && s.paceMinSPerKm)
            minimumDuration +=
              ((s.distanceM * s.paceMinSPerKm) / 1000) * b.repeatCount;
        }
      if (w.estimatedDurationS < minimumDuration)
        fail(
          "SESSION_DURATION_CONFLICT",
          "The duration estimate is shorter than its prescribed work.",
        );
    } else {
      if (!manifest.richStrength)
        fail(
          "DEVICE_EXECUTION_LIMIT",
          "This device cannot preserve rich strength targets.",
        );
      for (const e of w.strength.exercises) {
        const catalog =
          await sql`select id from exercises where id=${e.exerciseId}`;
        if (!catalog.length)
          fail("EXERCISE_UNAVAILABLE", "Select catalog exercises.");
        if (
          state.exercisePreferences.some(
            (p) =>
              p.exercise_id === e.exerciseId &&
              ["exclude", "avoid"].includes(String(p.preference)),
          )
        )
          fail("EXERCISE_EXCLUDED", "The athlete excluded this exercise.");
        const eq =
          await sql`select equipment_id from exercise_equipment where exercise_id=${e.exerciseId} and required=true`;
        if (
          eq.some(
            (e) =>
              !state.equipment.some(
                (a) => a.equipment_id === e.equipment_id && a.available,
              ),
          )
        )
          fail(
            "EQUIPMENT_UNAVAILABLE",
            "An exercise requires unavailable equipment.",
          );
        for (const s of e.sets) {
          if (
            s.repsMin == null ||
            s.repsMax == null ||
            s.repsMin < 1 ||
            (s.loadKg == null && s.rpeMin == null && s.rirMin == null)
          )
            fail(
              "INCOMPLETE_STRENGTH_TARGET",
              "Every set requires positive reps and a load, RPE or RIR target.",
            );
          if (s.loadPercentE1rm != null)
            fail(
              "UNSUPPORTED_RELATIVE_LOAD",
              "Use RPE/RIR or a supported recent absolute load; a verified E1RM is not available in this compiler.",
            );
          if ((s.repsMax ?? 0) > 100)
            fail(
              "STRENGTH_TARGET_LIMIT",
              "A set exceeds the operational repetition limit.",
            );
          if (s.loadKg != null && s.loadKg > 0) {
            const [known] =
              await sql`select max(s.load_kg)::float as load from strength_set_results s join strength_exercise_results e on e.id=s.exercise_result_id join workout_results r on r.id=e.workout_result_id where r.athlete_id=${String(athlete.id)} and r.deleted_at is null and e.exercise_id=${e.exerciseId} and s.status='completed' and s.load_convention='external' and r.training_date>=(now() at time zone ${String(athlete.timezone)})::date-90`;
            if (!known?.load || s.loadKg > Number(known.load))
              fail(
                "UNSUPPORTED_LOAD_TARGET",
                "Use RPE/RIR when an exercise load is unknown or above recorded capacity.",
              );
          }
        }
      }
    }
  }
  const prescriptionRows = all.reduce(
    (n, w) =>
      n +
      (w.discipline === "running"
        ? w.run.blocks.reduce((m, b) => m + 1 + b.steps.length, 0)
        : w.strength.exercises.reduce((m, e) => m + 1 + e.sets.length, 0)),
    0,
  );
  if (prescriptionRows > 20000)
    fail(
      "PLAN_SIZE_LIMIT",
      "Expanded prescriptions exceed the 20,000-row plan budget.",
    );
  if (!state.baseline)
    issues.push({
      code: "BASELINE_NOT_CONFIRMED",
      message:
        "No baseline snapshot is available. Starting doses require conservative effort targets and athlete review; no individual safe progression rate is established.",
    });
  if (all.length < 1 || all.length > 300)
    fail("PLAN_SIZE_LIMIT", "Plans must contain 1–300 sessions.");
  return issues;
}
export function contextSnapshot(
  state: Awaited<ReturnType<typeof planningState>>,
) {
  if (!state.policy || !state.preferences[0])
    fail(
      "PLANNING_PROFILE_INCOMPLETE",
      "A published policy and training preferences are required.",
    );
  return PlanningContextInput.parse({
    baselineSnapshotId: state.baseline?.id ?? null,
    schemaVersion: 1,
    policyVersionId: state.policy.id,
    snapshot: {
      goals: state.goals.map((r) => fields(GoalInput, r)),
      preferences: fields(PreferencesInput, state.preferences[0]),
      availabilityRules: state.availability.map((r) =>
        fields(AvailabilityRuleInput, r),
      ),
      availabilityOverrides: state.overrides.map((r) =>
        fields(AvailabilityOverrideInput, r),
      ),
      equipmentIds: state.equipment
        .filter((r) => r.available)
        .map((r) => r.equipment_id),
      recentFeatures: state.baseline?.metrics ?? {},
      ...(state.details
        ? {
            athleteDetailsId: state.details.id,
            athleteDetailsSnapshot: {
              revision: String(state.details.revision),
              details: state.details.details,
            },
          }
        : {}),
    },
  });
}

export function planReview(plan: StagedPlan) {
  const templates: unknown[] = [];
  const index = new Map<string, number>();
  const summarize = (workouts: Workout[]) =>
    workouts
      .filter((w) => plan.changed.includes(w.logicalWorkoutId))
      .map((w) => {
        const {
          logicalWorkoutId: _logical,
          scheduledDate: _date,
          scheduledStartAt: _instant,
          timezone: _zone,
          ...prescription
        } = semantic(w) as Row;
        const key = hash(prescription);
        if (!index.has(key)) {
          index.set(key, templates.length);
          templates.push(prescription);
        }
        return {
          logicalWorkoutId: w.logicalWorkoutId,
          date: w.scheduledDate,
          timezone: w.timezone,
          scheduledStartAt: w.scheduledStartAt,
          template: index.get(key),
        };
      });
  const before = summarize(plan.before),
    after = summarize(plan.after);
  const review = {
    rationale: plan.rationale,
    recurringPreference: plan.recurringPreference,
    before,
    after,
    templates,
  };
  if (Buffer.byteLength(JSON.stringify(review)) > 96000)
    fail(
      "AGENT_REVIEW_TOO_LARGE",
      "This change exceeds the bounded review context; request a smaller edit.",
    );
  return review;
}
