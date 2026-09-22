import { sql } from "drizzle-orm";
import {
  bigint,
  boolean,
  check,
  date,
  index,
  integer,
  jsonb,
  numeric,
  pgTable,
  primaryKey,
  text,
  timestamp,
  unique,
  uuid,
} from "drizzle-orm/pg-core";
import { athletes, trainingPolicyVersions } from "./foundation";

const id = () => uuid("id").primaryKey();
const owner = () =>
  uuid("athlete_id")
    .notNull()
    .references(() => athletes.id, { onDelete: "cascade" });
const instant = (name: string) => timestamp(name, { withTimezone: true });
const created = () => instant("created_at").notNull().defaultNow();
const mutable = () => ({
  createdAt: created(),
  updatedAt: instant("updated_at").notNull().defaultNow(),
  revision: bigint("revision", { mode: "bigint" }).notNull().default(sql`1`),
  deletedAt: instant("deleted_at"),
});
const json = (name: string) => jsonb(name).$type<Record<string, unknown>>();
const kg = (name: string) => numeric(name, { precision: 8, scale: 3 });
const effort = (name: string) => numeric(name, { precision: 3, scale: 1 });

export const athleteGoals = pgTable(
  "athlete_goals",
  {
    id: id(),
    athleteId: owner(),
    discipline: text("discipline").notNull(),
    goalType: text("goal_type").notNull(),
    status: text("status").notNull(),
    targetDate: date("target_date"),
    targetValue: numeric("target_value"),
    targetUnit: text("target_unit"),
    priorityRank: integer("priority_rank"),
    metadata: json("metadata").notNull(),
    ...mutable(),
  },
  (t) => [index("goals_owner_idx").on(t.athleteId)],
);
export const athleteTrainingPreferences = pgTable(
  "athlete_training_preferences",
  {
    id: id(),
    athleteId: owner().unique(),
    priorityMode: text("priority_mode").notNull(),
    runPriorityWeight: numeric("run_priority_weight", {
      precision: 4,
      scale: 3,
    }).notNull(),
    strengthPriorityWeight: numeric("strength_priority_weight", {
      precision: 4,
      scale: 3,
    }).notNull(),
    strengthObjective: text("strength_objective").notNull(),
    experienceLevel: text("experience_level"),
    notes: text("notes"),
    ...mutable(),
  },
  (t) => [
    check(
      "priority_weights",
      sql`${t.runPriorityWeight} >= 0 and ${t.strengthPriorityWeight} >= 0 and ${t.runPriorityWeight} + ${t.strengthPriorityWeight} = 1`,
    ),
  ],
);
export const athleteAvailabilityRules = pgTable(
  "athlete_availability_rules",
  {
    id: id(),
    athleteId: owner(),
    dayOfWeek: integer("day_of_week").notNull(),
    available: boolean("available").notNull(),
    maxSessions: integer("max_sessions").notNull(),
    minSessionMinutes: integer("min_session_minutes"),
    maxSessionMinutes: integer("max_session_minutes"),
    preference: text("preference").notNull(),
    ...mutable(),
  },
  (t) => [
    unique("availability_day_unique").on(t.athleteId, t.dayOfWeek),
    check("availability_day", sql`${t.dayOfWeek} between 1 and 7`),
  ],
);
export const athleteAvailabilityOverrides = pgTable(
  "athlete_availability_overrides",
  {
    id: id(),
    athleteId: owner(),
    date: date("date").notNull(),
    available: boolean("available").notNull(),
    maxSessions: integer("max_sessions"),
    maxSessionMinutes: integer("max_session_minutes"),
    reason: text("reason"),
    ...mutable(),
  },
  (t) => [unique("availability_date_unique").on(t.athleteId, t.date)],
);
export const baselineSnapshots = pgTable(
  "baseline_snapshots",
  {
    id: id(),
    athleteId: owner(),
    periodStart: date("period_start").notNull(),
    periodEnd: date("period_end").notNull(),
    schemaVersion: integer("schema_version").notNull(),
    metrics: json("metrics").notNull(),
    confidence: json("confidence").notNull(),
    source: text("source").notNull(),
    confirmedAt: instant("confirmed_at"),
    ...mutable(),
  },
  (t) => [
    index("baseline_owner_idx").on(t.athleteId),
    check("baseline_period", sql`${t.periodStart} <= ${t.periodEnd}`),
  ],
);
export const planningContextSnapshots = pgTable(
  "planning_context_snapshots",
  {
    id: id(),
    athleteId: owner(),
    baselineSnapshotId: uuid("baseline_snapshot_id").references(
      () => baselineSnapshots.id,
    ),
    schemaVersion: integer("schema_version").notNull(),
    policyVersionId: uuid("policy_version_id")
      .notNull()
      .references(() => trainingPolicyVersions.id),
    snapshot: json("snapshot").notNull(),
    checksum: text("checksum").notNull(),
    ...mutable(),
  },
  (t) => [index("context_owner_idx").on(t.athleteId)],
);

export const exercises = pgTable("exercises", {
  id: id(),
  slug: text("slug").notNull().unique(),
  name: text("name").notNull(),
  movementPattern: text("movement_pattern"),
  unilateral: boolean("unilateral").notNull().default(false),
  active: boolean("active").notNull().default(true),
  metadata: json("metadata").notNull().default({}),
});
export const equipment = pgTable("equipment", {
  id: id(),
  slug: text("slug").notNull().unique(),
  name: text("name").notNull(),
});
export const muscleGroups = pgTable("muscle_groups", {
  id: id(),
  slug: text("slug").notNull().unique(),
  name: text("name").notNull(),
});
export const exerciseAliases = pgTable(
  "exercise_aliases",
  {
    id: id(),
    exerciseId: uuid("exercise_id")
      .notNull()
      .references(() => exercises.id),
    source: text("source").notNull(),
    alias: text("alias").notNull(),
  },
  (t) => [unique("exercise_alias_unique").on(t.exerciseId, t.source, t.alias)],
);
export const exerciseMuscles = pgTable(
  "exercise_muscles",
  {
    exerciseId: uuid("exercise_id")
      .notNull()
      .references(() => exercises.id),
    muscleGroupId: uuid("muscle_group_id")
      .notNull()
      .references(() => muscleGroups.id),
    role: text("role").notNull(),
  },
  (t) => [primaryKey({ columns: [t.exerciseId, t.muscleGroupId] })],
);
export const exerciseEquipment = pgTable(
  "exercise_equipment",
  {
    exerciseId: uuid("exercise_id")
      .notNull()
      .references(() => exercises.id),
    equipmentId: uuid("equipment_id")
      .notNull()
      .references(() => equipment.id),
    required: boolean("required").notNull(),
  },
  (t) => [primaryKey({ columns: [t.exerciseId, t.equipmentId] })],
);
export const athleteEquipment = pgTable(
  "athlete_equipment",
  {
    id: id(),
    athleteId: owner(),
    equipmentId: uuid("equipment_id")
      .notNull()
      .references(() => equipment.id),
    available: boolean("available").notNull(),
    ...mutable(),
  },
  (t) => [unique("athlete_equipment_unique").on(t.athleteId, t.equipmentId)],
);
export const athleteExercisePreferences = pgTable(
  "athlete_exercise_preferences",
  {
    id: id(),
    athleteId: owner(),
    exerciseId: uuid("exercise_id")
      .notNull()
      .references(() => exercises.id),
    preference: text("preference").notNull(),
    notes: text("notes"),
    ...mutable(),
  },
  (t) => [unique("athlete_exercise_unique").on(t.athleteId, t.exerciseId)],
);

export const trainingBlocks = pgTable(
  "training_blocks",
  {
    id: id(),
    athleteId: owner(),
    name: text("name").notNull(),
    startDate: date("start_date").notNull(),
    endDate: date("end_date").notNull(),
    phase: text("phase").notNull(),
    status: text("status").notNull(),
    activePlanVersionId: uuid("active_plan_version_id"),
    ...mutable(),
  },
  (t) => [
    index("blocks_owner_idx").on(t.athleteId),
    check("block_dates", sql`${t.startDate} <= ${t.endDate}`),
  ],
);
export const planVersions = pgTable(
  "plan_versions",
  {
    id: id(),
    athleteId: owner(),
    trainingBlockId: uuid("training_block_id")
      .notNull()
      .references(() => trainingBlocks.id, { onDelete: "cascade" }),
    versionNumber: integer("version_number").notNull(),
    basePlanVersionId: uuid("base_plan_version_id"),
    planningContextSnapshotId: uuid("planning_context_snapshot_id")
      .notNull()
      .references(() => planningContextSnapshots.id),
    policyVersionId: uuid("policy_version_id")
      .notNull()
      .references(() => trainingPolicyVersions.id),
    origin: text("origin").notNull(),
    status: text("status").notNull().default("draft"),
    summary: text("summary"),
    activatedAt: instant("activated_at"),
    ...mutable(),
  },
  (t) => [
    unique("plan_version_number_unique").on(t.trainingBlockId, t.versionNumber),
    index("plans_owner_idx").on(t.athleteId),
    check(
      "plan_status",
      sql`${t.status} in ('draft','active','superseded','rejected')`,
    ),
  ],
);
export const plannedWorkouts = pgTable(
  "planned_workouts",
  {
    id: id(),
    planVersionId: uuid("plan_version_id")
      .notNull()
      .references(() => planVersions.id, { onDelete: "cascade" }),
    logicalWorkoutId: uuid("logical_workout_id").notNull(),
    discipline: text("discipline").notNull(),
    workoutType: text("workout_type").notNull(),
    scheduledDate: date("scheduled_date").notNull(),
    scheduledStartAt: instant("scheduled_start_at"),
    timezone: text("timezone").notNull(),
    title: text("title").notNull(),
    purpose: text("purpose"),
    priority: text("priority").notNull(),
    estimatedDurationS: integer("estimated_duration_s"),
    plannedDistanceM: integer("planned_distance_m"),
    instructions: text("instructions"),
    createdAt: created(),
  },
  (t) => [
    unique("plan_logical_unique").on(t.planVersionId, t.logicalWorkoutId),
    index("planned_date_idx").on(t.planVersionId, t.scheduledDate),
  ],
);
export const runPrescriptions = pgTable("run_prescriptions", {
  plannedWorkoutId: uuid("planned_workout_id")
    .primaryKey()
    .references(() => plannedWorkouts.id, { onDelete: "cascade" }),
  primaryTargetType: text("primary_target_type").notNull(),
  notes: text("notes"),
});
export const runPrescriptionBlocks = pgTable(
  "run_prescription_blocks",
  {
    id: id(),
    plannedWorkoutId: uuid("planned_workout_id")
      .notNull()
      .references(() => runPrescriptions.plannedWorkoutId, {
        onDelete: "cascade",
      }),
    sequence: integer("sequence").notNull(),
    repeatCount: integer("repeat_count").notNull(),
    label: text("label"),
  },
  (t) => [
    unique("run_block_sequence_unique").on(t.plannedWorkoutId, t.sequence),
  ],
);
export const runPrescriptionSteps = pgTable(
  "run_prescription_steps",
  {
    id: id(),
    blockId: uuid("block_id")
      .notNull()
      .references(() => runPrescriptionBlocks.id, { onDelete: "cascade" }),
    sequence: integer("sequence").notNull(),
    stepKind: text("step_kind").notNull(),
    distanceM: integer("distance_m"),
    durationS: integer("duration_s"),
    paceMinSPerKm: numeric("pace_min_s_per_km"),
    paceMaxSPerKm: numeric("pace_max_s_per_km"),
    hrMinBpm: integer("hr_min_bpm"),
    hrMaxBpm: integer("hr_max_bpm"),
    rpeMin: effort("rpe_min"),
    rpeMax: effort("rpe_max"),
    notes: text("notes"),
  },
  (t) => [unique("run_step_sequence_unique").on(t.blockId, t.sequence)],
);
export const strengthPrescriptions = pgTable("strength_prescriptions", {
  plannedWorkoutId: uuid("planned_workout_id")
    .primaryKey()
    .references(() => plannedWorkouts.id, { onDelete: "cascade" }),
  sessionFocus: text("session_focus").notNull(),
  notes: text("notes"),
});
export const strengthExercisePrescriptions = pgTable(
  "strength_exercise_prescriptions",
  {
    id: id(),
    plannedWorkoutId: uuid("planned_workout_id")
      .notNull()
      .references(() => strengthPrescriptions.plannedWorkoutId, {
        onDelete: "cascade",
      }),
    exerciseId: uuid("exercise_id")
      .notNull()
      .references(() => exercises.id),
    sequence: integer("sequence").notNull(),
    supersetGroupId: uuid("superset_group_id"),
    substitutionAllowed: boolean("substitution_allowed").notNull(),
    notes: text("notes"),
  },
  (t) => [
    unique("strength_exercise_sequence_unique").on(
      t.plannedWorkoutId,
      t.sequence,
    ),
  ],
);
export const strengthSetPrescriptions = pgTable(
  "strength_set_prescriptions",
  {
    id: id(),
    exercisePrescriptionId: uuid("exercise_prescription_id")
      .notNull()
      .references(() => strengthExercisePrescriptions.id, {
        onDelete: "cascade",
      }),
    setNumber: integer("set_number").notNull(),
    setKind: text("set_kind").notNull(),
    repsMin: integer("reps_min"),
    repsMax: integer("reps_max"),
    loadKg: kg("load_kg"),
    loadPercentE1rm: numeric("load_percent_e1rm", { precision: 5, scale: 2 }),
    rpeMin: effort("rpe_min"),
    rpeMax: effort("rpe_max"),
    rirMin: effort("rir_min"),
    rirMax: effort("rir_max"),
    restS: integer("rest_s"),
    notes: text("notes"),
  },
  (t) => [
    unique("prescribed_set_number_unique").on(
      t.exercisePrescriptionId,
      t.setNumber,
    ),
    check(
      "prescribed_load_positive",
      sql`${t.loadKg} is null or ${t.loadKg} >= 0`,
    ),
  ],
);
export const strengthSubstitutionOptions = pgTable(
  "strength_substitution_options",
  {
    exercisePrescriptionId: uuid("exercise_prescription_id")
      .notNull()
      .references(() => strengthExercisePrescriptions.id, {
        onDelete: "cascade",
      }),
    substituteExerciseId: uuid("substitute_exercise_id")
      .notNull()
      .references(() => exercises.id),
    priority: integer("priority").notNull(),
    rationale: text("rationale"),
  },
  (t) => [
    primaryKey({ columns: [t.exercisePrescriptionId, t.substituteExerciseId] }),
  ],
);

export const workoutResults = pgTable(
  "workout_results",
  {
    id: id(),
    athleteId: owner(),
    plannedWorkoutId: uuid("planned_workout_id").references(
      () => plannedWorkouts.id,
    ),
    logicalWorkoutId: uuid("logical_workout_id"),
    discipline: text("discipline").notNull(),
    trainingDate: date("training_date").notNull(),
    timezone: text("timezone").notNull(),
    dateBasis: text("date_basis").notNull().default("performedDate"),
    loggedAt: instant("logged_at"),
    durationS: integer("duration_s"),
    startedAt: instant("started_at"),
    endedAt: instant("ended_at"),
    completionStatus: text("completion_status").notNull(),
    sourceType: text("source_type").notNull(),
    sessionRpe: effort("session_rpe"),
    notes: text("notes"),
    ...mutable(),
  },
  (t) => [
    index("results_owner_date_idx").on(t.athleteId, t.trainingDate),
    check(
      "result_date_basis",
      sql`${t.dateBasis} in ('performedDate', 'loggedDate')`,
    ),
    check(
      "result_duration",
      sql`${t.durationS} is null or ${t.durationS} between 0 and 604800`,
    ),
    check(
      "result_times",
      sql`${t.endedAt} is null or ${t.startedAt} is null or ${t.endedAt} >= ${t.startedAt}`,
    ),
  ],
);
export const runResults = pgTable(
  "run_results",
  {
    workoutResultId: uuid("workout_result_id")
      .primaryKey()
      .references(() => workoutResults.id, { onDelete: "cascade" }),
    distanceM: integer("distance_m").notNull(),
    durationS: integer("duration_s").notNull(),
    movingDurationS: integer("moving_duration_s"),
    avgHrBpm: integer("avg_hr_bpm"),
    maxHrBpm: integer("max_hr_bpm"),
    elevationGainM: numeric("elevation_gain_m"),
    avgCadenceSpm: numeric("avg_cadence_spm"),
    hrZoneSummary: jsonb("hr_zone_summary").notNull(),
  },
  (t) => [
    check(
      "run_totals_nonnegative",
      sql`${t.distanceM} >= 0 and ${t.durationS} >= 0`,
    ),
  ],
);
export const runResultSegments = pgTable(
  "run_result_segments",
  {
    id: id(),
    workoutResultId: uuid("workout_result_id")
      .notNull()
      .references(() => runResults.workoutResultId, { onDelete: "cascade" }),
    prescriptionStepId: uuid("prescription_step_id").references(
      () => runPrescriptionSteps.id,
    ),
    segmentType: text("segment_type").notNull(),
    sequence: integer("sequence").notNull(),
    repeatIteration: integer("repeat_iteration"),
    distanceM: integer("distance_m"),
    durationS: integer("duration_s").notNull(),
    avgHrBpm: integer("avg_hr_bpm"),
    maxHrBpm: integer("max_hr_bpm"),
    elevationGainM: numeric("elevation_gain_m"),
    avgCadenceSpm: numeric("avg_cadence_spm"),
    startOffsetS: integer("start_offset_s"),
  },
  (t) => [
    unique("result_segment_sequence_unique").on(t.workoutResultId, t.sequence),
  ],
);
export const strengthExerciseResults = pgTable(
  "strength_exercise_results",
  {
    id: id(),
    workoutResultId: uuid("workout_result_id")
      .notNull()
      .references(() => workoutResults.id, { onDelete: "cascade" }),
    prescribedExerciseId: uuid("prescribed_exercise_id").references(
      () => strengthExercisePrescriptions.id,
    ),
    exerciseId: uuid("exercise_id")
      .notNull()
      .references(() => exercises.id),
    sequence: integer("sequence").notNull(),
    notes: text("notes"),
    substitutionReason: text("substitution_reason"),
  },
  (t) => [
    unique("result_exercise_sequence_unique").on(t.workoutResultId, t.sequence),
  ],
);
export const strengthSetResults = pgTable(
  "strength_set_results",
  {
    id: id(),
    exerciseResultId: uuid("exercise_result_id")
      .notNull()
      .references(() => strengthExerciseResults.id, { onDelete: "cascade" }),
    prescribedSetId: uuid("prescribed_set_id").references(
      () => strengthSetPrescriptions.id,
    ),
    setNumber: integer("set_number").notNull(),
    setKind: text("set_kind").notNull(),
    reps: integer("reps"),
    loadKg: kg("load_kg"),
    loadConvention: text("load_convention").notNull().default("external"),
    rpe: effort("rpe"),
    rir: effort("rir"),
    status: text("status").notNull(),
    completedAt: instant("completed_at"),
  },
  (t) => [
    unique("actual_set_number_unique").on(t.exerciseResultId, t.setNumber),
    check(
      "actual_load_convention",
      sql`${t.loadConvention} in ('external', 'bodyweight', 'assistance')`,
    ),
    check("actual_load_positive", sql`${t.loadKg} is null or ${t.loadKg} >= 0`),
  ],
);
export const activitySourceRecords = pgTable(
  "activity_source_records",
  {
    id: id(),
    athleteId: owner(),
    provider: text("provider").notNull(),
    externalId: text("external_id").notNull(),
    fingerprint: text("fingerprint").notNull(),
    workoutResultId: uuid("workout_result_id").references(
      () => workoutResults.id,
    ),
    sourceCreatedAt: instant("source_created_at"),
    sourceUpdatedAt: instant("source_updated_at"),
    sourceDeletedAt: instant("source_deleted_at"),
    importStatus: text("import_status").notNull(),
    matchStatus: text("match_status").notNull(),
    matchConfidence: numeric("match_confidence", { precision: 5, scale: 4 }),
    matchedLogicalWorkoutId: uuid("matched_logical_workout_id"),
    metadata: json("metadata").notNull(),
    ...mutable(),
  },
  (t) => [
    unique("source_external_unique").on(t.athleteId, t.provider, t.externalId),
    unique("source_fingerprint_unique").on(
      t.athleteId,
      t.provider,
      t.fingerprint,
    ),
  ],
);

export const planChangeSets = pgTable(
  "plan_change_sets",
  {
    id: id(),
    athleteId: owner(),
    fromPlanVersionId: uuid("from_plan_version_id").references(
      () => planVersions.id,
    ),
    toPlanVersionId: uuid("to_plan_version_id")
      .notNull()
      .references(() => planVersions.id, { onDelete: "cascade" }),
    origin: text("origin").notNull(),
    reasonCode: text("reason_code").notNull(),
    explanation: text("explanation").notNull(),
    material: boolean("material").notNull(),
    proposalId: uuid("proposal_id"),
    acceptedAt: instant("accepted_at").notNull(),
    createdAt: created(),
  },
  (t) => [index("change_sets_owner_idx").on(t.athleteId)],
);
export const planChangeItems = pgTable("plan_change_items", {
  id: id(),
  changeSetId: uuid("change_set_id")
    .notNull()
    .references(() => planChangeSets.id, { onDelete: "cascade" }),
  logicalWorkoutId: uuid("logical_workout_id").notNull(),
  changeType: text("change_type").notNull(),
  beforePlannedWorkoutId: uuid("before_planned_workout_id").references(
    () => plannedWorkouts.id,
  ),
  afterPlannedWorkoutId: uuid("after_planned_workout_id").references(
    () => plannedWorkouts.id,
  ),
  changes: json("changes").notNull(),
});
