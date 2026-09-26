CREATE TABLE "activity_source_records" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"provider" text NOT NULL,
	"external_id" text NOT NULL,
	"fingerprint" text NOT NULL,
	"workout_result_id" uuid,
	"source_created_at" timestamp with time zone,
	"source_updated_at" timestamp with time zone,
	"source_deleted_at" timestamp with time zone,
	"import_status" text NOT NULL,
	"match_status" text NOT NULL,
	"match_confidence" numeric(5, 4),
	"matched_logical_workout_id" uuid,
	"metadata" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "source_external_unique" UNIQUE("athlete_id","provider","external_id"),
	CONSTRAINT "source_fingerprint_unique" UNIQUE("athlete_id","provider","fingerprint")
);
--> statement-breakpoint
CREATE TABLE "athlete_availability_overrides" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"date" date NOT NULL,
	"available" boolean NOT NULL,
	"max_sessions" integer,
	"max_session_minutes" integer,
	"reason" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "availability_date_unique" UNIQUE("athlete_id","date")
);
--> statement-breakpoint
CREATE TABLE "athlete_availability_rules" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"day_of_week" integer NOT NULL,
	"available" boolean NOT NULL,
	"max_sessions" integer NOT NULL,
	"min_session_minutes" integer,
	"max_session_minutes" integer,
	"preference" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "availability_day_unique" UNIQUE("athlete_id","day_of_week"),
	CONSTRAINT "availability_day" CHECK ("athlete_availability_rules"."day_of_week" between 1 and 7)
);
--> statement-breakpoint
CREATE TABLE "athlete_equipment" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"equipment_id" uuid NOT NULL,
	"available" boolean NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "athlete_equipment_unique" UNIQUE("athlete_id","equipment_id")
);
--> statement-breakpoint
CREATE TABLE "athlete_exercise_preferences" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"exercise_id" uuid NOT NULL,
	"preference" text NOT NULL,
	"notes" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "athlete_exercise_unique" UNIQUE("athlete_id","exercise_id")
);
--> statement-breakpoint
CREATE TABLE "athlete_goals" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"discipline" text NOT NULL,
	"goal_type" text NOT NULL,
	"status" text NOT NULL,
	"target_date" date,
	"target_value" numeric,
	"target_unit" text,
	"priority_rank" integer,
	"metadata" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "athlete_training_preferences" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"priority_mode" text NOT NULL,
	"run_priority_weight" numeric(4, 3) NOT NULL,
	"strength_priority_weight" numeric(4, 3) NOT NULL,
	"strength_objective" text NOT NULL,
	"experience_level" text,
	"notes" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "athlete_training_preferences_athlete_id_unique" UNIQUE("athlete_id"),
	CONSTRAINT "priority_weights" CHECK ("athlete_training_preferences"."run_priority_weight" >= 0 and "athlete_training_preferences"."strength_priority_weight" >= 0 and "athlete_training_preferences"."run_priority_weight" + "athlete_training_preferences"."strength_priority_weight" = 1)
);
--> statement-breakpoint
CREATE TABLE "baseline_snapshots" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"period_start" date NOT NULL,
	"period_end" date NOT NULL,
	"schema_version" integer NOT NULL,
	"metrics" jsonb NOT NULL,
	"confidence" jsonb NOT NULL,
	"source" text NOT NULL,
	"confirmed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "baseline_period" CHECK ("baseline_snapshots"."period_start" <= "baseline_snapshots"."period_end")
);
--> statement-breakpoint
CREATE TABLE "equipment" (
	"id" uuid PRIMARY KEY NOT NULL,
	"slug" text NOT NULL,
	"name" text NOT NULL,
	CONSTRAINT "equipment_slug_unique" UNIQUE("slug")
);
--> statement-breakpoint
CREATE TABLE "exercise_aliases" (
	"id" uuid PRIMARY KEY NOT NULL,
	"exercise_id" uuid NOT NULL,
	"source" text NOT NULL,
	"alias" text NOT NULL,
	CONSTRAINT "exercise_alias_unique" UNIQUE("exercise_id","source","alias")
);
--> statement-breakpoint
CREATE TABLE "exercise_equipment" (
	"exercise_id" uuid NOT NULL,
	"equipment_id" uuid NOT NULL,
	"required" boolean NOT NULL,
	CONSTRAINT "exercise_equipment_exercise_id_equipment_id_pk" PRIMARY KEY("exercise_id","equipment_id")
);
--> statement-breakpoint
CREATE TABLE "exercise_muscles" (
	"exercise_id" uuid NOT NULL,
	"muscle_group_id" uuid NOT NULL,
	"role" text NOT NULL,
	CONSTRAINT "exercise_muscles_exercise_id_muscle_group_id_pk" PRIMARY KEY("exercise_id","muscle_group_id")
);
--> statement-breakpoint
CREATE TABLE "exercises" (
	"id" uuid PRIMARY KEY NOT NULL,
	"slug" text NOT NULL,
	"name" text NOT NULL,
	"movement_pattern" text,
	"unilateral" boolean DEFAULT false NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
	CONSTRAINT "exercises_slug_unique" UNIQUE("slug")
);
--> statement-breakpoint
CREATE TABLE "muscle_groups" (
	"id" uuid PRIMARY KEY NOT NULL,
	"slug" text NOT NULL,
	"name" text NOT NULL,
	CONSTRAINT "muscle_groups_slug_unique" UNIQUE("slug")
);
--> statement-breakpoint
CREATE TABLE "plan_change_items" (
	"id" uuid PRIMARY KEY NOT NULL,
	"change_set_id" uuid NOT NULL,
	"logical_workout_id" uuid NOT NULL,
	"change_type" text NOT NULL,
	"before_planned_workout_id" uuid,
	"after_planned_workout_id" uuid,
	"changes" jsonb NOT NULL
);
--> statement-breakpoint
CREATE TABLE "plan_change_sets" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"from_plan_version_id" uuid,
	"to_plan_version_id" uuid NOT NULL,
	"origin" text NOT NULL,
	"reason_code" text NOT NULL,
	"explanation" text NOT NULL,
	"material" boolean NOT NULL,
	"proposal_id" uuid,
	"accepted_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "plan_versions" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"training_block_id" uuid NOT NULL,
	"version_number" integer NOT NULL,
	"base_plan_version_id" uuid,
	"planning_context_snapshot_id" uuid NOT NULL,
	"policy_version_id" uuid NOT NULL,
	"origin" text NOT NULL,
	"status" text DEFAULT 'draft' NOT NULL,
	"summary" text,
	"activated_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "plan_version_number_unique" UNIQUE("training_block_id","version_number"),
	CONSTRAINT "plan_status" CHECK ("plan_versions"."status" in ('draft','active','superseded','rejected'))
);
--> statement-breakpoint
CREATE TABLE "planned_workouts" (
	"id" uuid PRIMARY KEY NOT NULL,
	"plan_version_id" uuid NOT NULL,
	"logical_workout_id" uuid NOT NULL,
	"discipline" text NOT NULL,
	"workout_type" text NOT NULL,
	"scheduled_date" date NOT NULL,
	"scheduled_start_at" timestamp with time zone,
	"timezone" text NOT NULL,
	"title" text NOT NULL,
	"purpose" text,
	"priority" text NOT NULL,
	"estimated_duration_s" integer,
	"planned_distance_m" integer,
	"instructions" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "plan_logical_unique" UNIQUE("plan_version_id","logical_workout_id")
);
--> statement-breakpoint
CREATE TABLE "planning_context_snapshots" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"baseline_snapshot_id" uuid,
	"schema_version" integer NOT NULL,
	"policy_version_id" uuid NOT NULL,
	"snapshot" jsonb NOT NULL,
	"checksum" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "run_prescription_blocks" (
	"id" uuid PRIMARY KEY NOT NULL,
	"planned_workout_id" uuid NOT NULL,
	"sequence" integer NOT NULL,
	"repeat_count" integer NOT NULL,
	"label" text,
	CONSTRAINT "run_block_sequence_unique" UNIQUE("planned_workout_id","sequence")
);
--> statement-breakpoint
CREATE TABLE "run_prescription_steps" (
	"id" uuid PRIMARY KEY NOT NULL,
	"block_id" uuid NOT NULL,
	"sequence" integer NOT NULL,
	"step_kind" text NOT NULL,
	"distance_m" integer,
	"duration_s" integer,
	"pace_min_s_per_km" numeric,
	"pace_max_s_per_km" numeric,
	"hr_min_bpm" integer,
	"hr_max_bpm" integer,
	"rpe_min" numeric(3, 1),
	"rpe_max" numeric(3, 1),
	"notes" text,
	CONSTRAINT "run_step_sequence_unique" UNIQUE("block_id","sequence")
);
--> statement-breakpoint
CREATE TABLE "run_prescriptions" (
	"planned_workout_id" uuid PRIMARY KEY NOT NULL,
	"primary_target_type" text NOT NULL,
	"notes" text
);
--> statement-breakpoint
CREATE TABLE "run_result_segments" (
	"id" uuid PRIMARY KEY NOT NULL,
	"workout_result_id" uuid NOT NULL,
	"prescription_step_id" uuid,
	"segment_type" text NOT NULL,
	"sequence" integer NOT NULL,
	"repeat_iteration" integer,
	"distance_m" integer,
	"duration_s" integer NOT NULL,
	"avg_hr_bpm" integer,
	"max_hr_bpm" integer,
	"elevation_gain_m" numeric,
	"avg_cadence_spm" numeric,
	"start_offset_s" integer,
	CONSTRAINT "result_segment_sequence_unique" UNIQUE("workout_result_id","sequence")
);
--> statement-breakpoint
CREATE TABLE "run_results" (
	"workout_result_id" uuid PRIMARY KEY NOT NULL,
	"distance_m" integer NOT NULL,
	"duration_s" integer NOT NULL,
	"moving_duration_s" integer,
	"avg_hr_bpm" integer,
	"max_hr_bpm" integer,
	"elevation_gain_m" numeric,
	"avg_cadence_spm" numeric,
	"hr_zone_summary" jsonb NOT NULL,
	CONSTRAINT "run_totals_nonnegative" CHECK ("run_results"."distance_m" >= 0 and "run_results"."duration_s" >= 0)
);
--> statement-breakpoint
CREATE TABLE "strength_exercise_prescriptions" (
	"id" uuid PRIMARY KEY NOT NULL,
	"planned_workout_id" uuid NOT NULL,
	"exercise_id" uuid NOT NULL,
	"sequence" integer NOT NULL,
	"superset_group_id" uuid,
	"substitution_allowed" boolean NOT NULL,
	"notes" text,
	CONSTRAINT "strength_exercise_sequence_unique" UNIQUE("planned_workout_id","sequence")
);
--> statement-breakpoint
CREATE TABLE "strength_exercise_results" (
	"id" uuid PRIMARY KEY NOT NULL,
	"workout_result_id" uuid NOT NULL,
	"prescribed_exercise_id" uuid,
	"exercise_id" uuid NOT NULL,
	"sequence" integer NOT NULL,
	"notes" text,
	"substitution_reason" text,
	CONSTRAINT "result_exercise_sequence_unique" UNIQUE("workout_result_id","sequence")
);
--> statement-breakpoint
CREATE TABLE "strength_prescriptions" (
	"planned_workout_id" uuid PRIMARY KEY NOT NULL,
	"session_focus" text NOT NULL,
	"notes" text
);
--> statement-breakpoint
CREATE TABLE "strength_set_prescriptions" (
	"id" uuid PRIMARY KEY NOT NULL,
	"exercise_prescription_id" uuid NOT NULL,
	"set_number" integer NOT NULL,
	"set_kind" text NOT NULL,
	"reps_min" integer,
	"reps_max" integer,
	"load_kg" numeric(8, 3),
	"load_percent_e1rm" numeric(5, 2),
	"rpe_min" numeric(3, 1),
	"rpe_max" numeric(3, 1),
	"rir_min" numeric(3, 1),
	"rir_max" numeric(3, 1),
	"rest_s" integer,
	"notes" text,
	CONSTRAINT "prescribed_set_number_unique" UNIQUE("exercise_prescription_id","set_number"),
	CONSTRAINT "prescribed_load_positive" CHECK ("strength_set_prescriptions"."load_kg" is null or "strength_set_prescriptions"."load_kg" >= 0)
);
--> statement-breakpoint
CREATE TABLE "strength_set_results" (
	"id" uuid PRIMARY KEY NOT NULL,
	"exercise_result_id" uuid NOT NULL,
	"prescribed_set_id" uuid,
	"set_number" integer NOT NULL,
	"set_kind" text NOT NULL,
	"reps" integer,
	"load_kg" numeric(8, 3),
	"rpe" numeric(3, 1),
	"rir" numeric(3, 1),
	"status" text NOT NULL,
	"completed_at" timestamp with time zone,
	CONSTRAINT "actual_set_number_unique" UNIQUE("exercise_result_id","set_number"),
	CONSTRAINT "actual_load_positive" CHECK ("strength_set_results"."load_kg" is null or "strength_set_results"."load_kg" >= 0)
);
--> statement-breakpoint
CREATE TABLE "strength_substitution_options" (
	"exercise_prescription_id" uuid NOT NULL,
	"substitute_exercise_id" uuid NOT NULL,
	"priority" integer NOT NULL,
	"rationale" text,
	CONSTRAINT "strength_substitution_options_exercise_prescription_id_substitute_exercise_id_pk" PRIMARY KEY("exercise_prescription_id","substitute_exercise_id")
);
--> statement-breakpoint
CREATE TABLE "training_blocks" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"name" text NOT NULL,
	"start_date" date NOT NULL,
	"end_date" date NOT NULL,
	"phase" text NOT NULL,
	"status" text NOT NULL,
	"active_plan_version_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "block_dates" CHECK ("training_blocks"."start_date" <= "training_blocks"."end_date")
);
--> statement-breakpoint
CREATE TABLE "workout_results" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"planned_workout_id" uuid,
	"logical_workout_id" uuid,
	"discipline" text NOT NULL,
	"training_date" date NOT NULL,
	"timezone" text NOT NULL,
	"started_at" timestamp with time zone,
	"ended_at" timestamp with time zone,
	"completion_status" text NOT NULL,
	"source_type" text NOT NULL,
	"session_rpe" numeric(3, 1),
	"notes" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "result_times" CHECK ("workout_results"."ended_at" is null or "workout_results"."started_at" is null or "workout_results"."ended_at" >= "workout_results"."started_at")
);
--> statement-breakpoint
CREATE TABLE "action_proposals" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"thread_id" uuid,
	"message_id" uuid,
	"base_plan_version_id" uuid,
	"action_type" text NOT NULL,
	"action_payload" jsonb NOT NULL,
	"rationale" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"accepted_at" timestamp with time zone,
	"applied_plan_version_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "ai_invocations" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"idempotency_key" uuid NOT NULL,
	"kind" text NOT NULL,
	"provider" text NOT NULL,
	"model" text NOT NULL,
	"feature" text NOT NULL,
	"prompt_version" text NOT NULL,
	"context_snapshot_id" uuid,
	"request_hash" text NOT NULL,
	"input_tokens" integer,
	"output_tokens" integer,
	"cost_usd_micros" bigint,
	"latency_ms" integer,
	"status" text NOT NULL,
	"provider_request_id" text,
	"response" jsonb,
	"error_code" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"finished_at" timestamp with time zone,
	CONSTRAINT "ai_request_unique" UNIQUE("athlete_id","idempotency_key")
);
--> statement-breakpoint
CREATE TABLE "coach_messages" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"thread_id" uuid NOT NULL,
	"role" text NOT NULL,
	"content" text NOT NULL,
	"ai_invocation_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "coach_threads" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"title" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "intelligence_context_snapshots" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"context_type" text NOT NULL,
	"schema_version" integer NOT NULL,
	"features" jsonb NOT NULL,
	"checksum" text NOT NULL,
	"retention_class" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "structured_decisions" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"invocation_id" uuid NOT NULL,
	"decision_type" text NOT NULL,
	"selected_choice" text NOT NULL,
	"result" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "apple_notifications" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid,
	"type" text NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "push_deliveries" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"device_id" uuid NOT NULL,
	"request_hash" text NOT NULL,
	"status" text NOT NULL,
	"reason" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "storekit_transactions" (
	"transaction_id" text PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"original_transaction_id" text NOT NULL,
	"product_id" text NOT NULL,
	"entitlement_key" text NOT NULL,
	"environment" text NOT NULL,
	"purchased_at" timestamp with time zone NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"grace_until" timestamp with time zone,
	"revoked_at" timestamp with time zone,
	"signed_at" timestamp with time zone NOT NULL,
	"verified_payload" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "athletes" DROP CONSTRAINT "athletes_auth_user_id_auth_user_id_fk";
--> statement-breakpoint
ALTER TABLE "device_installations" DROP CONSTRAINT "device_installations_athlete_id_athletes_id_fk";
--> statement-breakpoint
ALTER TABLE "entitlements" DROP CONSTRAINT "entitlements_athlete_id_athletes_id_fk";
--> statement-breakpoint
ALTER TABLE "device_sync_state" DROP CONSTRAINT "device_sync_state_athlete_id_athletes_id_fk";
--> statement-breakpoint
ALTER TABLE "device_sync_state" DROP CONSTRAINT "device_sync_state_device_id_athlete_id_device_installations_id_athlete_id_fk";
--> statement-breakpoint
ALTER TABLE "sync_change_log" DROP CONSTRAINT "sync_change_log_athlete_id_athletes_id_fk";
--> statement-breakpoint
ALTER TABLE "sync_mutations" DROP CONSTRAINT "sync_mutations_athlete_id_athletes_id_fk";
--> statement-breakpoint
ALTER TABLE "sync_mutations" DROP CONSTRAINT "sync_mutations_device_id_athlete_id_device_installations_id_athlete_id_fk";
--> statement-breakpoint
ALTER TABLE "athletes" ADD COLUMN "cloud_ai_consent" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "device_installations" ADD COLUMN "push_environment" text DEFAULT 'sandbox' NOT NULL;--> statement-breakpoint
ALTER TABLE "entitlements" ADD COLUMN "id" uuid DEFAULT gen_random_uuid() NOT NULL;--> statement-breakpoint
ALTER TABLE "activity_source_records" ADD CONSTRAINT "activity_source_records_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activity_source_records" ADD CONSTRAINT "activity_source_records_workout_result_id_workout_results_id_fk" FOREIGN KEY ("workout_result_id") REFERENCES "public"."workout_results"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "athlete_availability_overrides" ADD CONSTRAINT "athlete_availability_overrides_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "athlete_availability_rules" ADD CONSTRAINT "athlete_availability_rules_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "athlete_equipment" ADD CONSTRAINT "athlete_equipment_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "athlete_equipment" ADD CONSTRAINT "athlete_equipment_equipment_id_equipment_id_fk" FOREIGN KEY ("equipment_id") REFERENCES "public"."equipment"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "athlete_exercise_preferences" ADD CONSTRAINT "athlete_exercise_preferences_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "athlete_exercise_preferences" ADD CONSTRAINT "athlete_exercise_preferences_exercise_id_exercises_id_fk" FOREIGN KEY ("exercise_id") REFERENCES "public"."exercises"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "athlete_goals" ADD CONSTRAINT "athlete_goals_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "athlete_training_preferences" ADD CONSTRAINT "athlete_training_preferences_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "baseline_snapshots" ADD CONSTRAINT "baseline_snapshots_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_aliases" ADD CONSTRAINT "exercise_aliases_exercise_id_exercises_id_fk" FOREIGN KEY ("exercise_id") REFERENCES "public"."exercises"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_equipment" ADD CONSTRAINT "exercise_equipment_exercise_id_exercises_id_fk" FOREIGN KEY ("exercise_id") REFERENCES "public"."exercises"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_equipment" ADD CONSTRAINT "exercise_equipment_equipment_id_equipment_id_fk" FOREIGN KEY ("equipment_id") REFERENCES "public"."equipment"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_muscles" ADD CONSTRAINT "exercise_muscles_exercise_id_exercises_id_fk" FOREIGN KEY ("exercise_id") REFERENCES "public"."exercises"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_muscles" ADD CONSTRAINT "exercise_muscles_muscle_group_id_muscle_groups_id_fk" FOREIGN KEY ("muscle_group_id") REFERENCES "public"."muscle_groups"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan_change_items" ADD CONSTRAINT "plan_change_items_change_set_id_plan_change_sets_id_fk" FOREIGN KEY ("change_set_id") REFERENCES "public"."plan_change_sets"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan_change_items" ADD CONSTRAINT "plan_change_items_before_planned_workout_id_planned_workouts_id_fk" FOREIGN KEY ("before_planned_workout_id") REFERENCES "public"."planned_workouts"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan_change_items" ADD CONSTRAINT "plan_change_items_after_planned_workout_id_planned_workouts_id_fk" FOREIGN KEY ("after_planned_workout_id") REFERENCES "public"."planned_workouts"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan_change_sets" ADD CONSTRAINT "plan_change_sets_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan_change_sets" ADD CONSTRAINT "plan_change_sets_from_plan_version_id_plan_versions_id_fk" FOREIGN KEY ("from_plan_version_id") REFERENCES "public"."plan_versions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan_change_sets" ADD CONSTRAINT "plan_change_sets_to_plan_version_id_plan_versions_id_fk" FOREIGN KEY ("to_plan_version_id") REFERENCES "public"."plan_versions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan_versions" ADD CONSTRAINT "plan_versions_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan_versions" ADD CONSTRAINT "plan_versions_training_block_id_training_blocks_id_fk" FOREIGN KEY ("training_block_id") REFERENCES "public"."training_blocks"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan_versions" ADD CONSTRAINT "plan_versions_planning_context_snapshot_id_planning_context_snapshots_id_fk" FOREIGN KEY ("planning_context_snapshot_id") REFERENCES "public"."planning_context_snapshots"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "plan_versions" ADD CONSTRAINT "plan_versions_policy_version_id_training_policy_versions_id_fk" FOREIGN KEY ("policy_version_id") REFERENCES "public"."training_policy_versions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "planned_workouts" ADD CONSTRAINT "planned_workouts_plan_version_id_plan_versions_id_fk" FOREIGN KEY ("plan_version_id") REFERENCES "public"."plan_versions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "planning_context_snapshots" ADD CONSTRAINT "planning_context_snapshots_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "planning_context_snapshots" ADD CONSTRAINT "planning_context_snapshots_baseline_snapshot_id_baseline_snapshots_id_fk" FOREIGN KEY ("baseline_snapshot_id") REFERENCES "public"."baseline_snapshots"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "planning_context_snapshots" ADD CONSTRAINT "planning_context_snapshots_policy_version_id_training_policy_versions_id_fk" FOREIGN KEY ("policy_version_id") REFERENCES "public"."training_policy_versions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_prescription_blocks" ADD CONSTRAINT "run_prescription_blocks_planned_workout_id_run_prescriptions_planned_workout_id_fk" FOREIGN KEY ("planned_workout_id") REFERENCES "public"."run_prescriptions"("planned_workout_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_prescription_steps" ADD CONSTRAINT "run_prescription_steps_block_id_run_prescription_blocks_id_fk" FOREIGN KEY ("block_id") REFERENCES "public"."run_prescription_blocks"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_prescriptions" ADD CONSTRAINT "run_prescriptions_planned_workout_id_planned_workouts_id_fk" FOREIGN KEY ("planned_workout_id") REFERENCES "public"."planned_workouts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_result_segments" ADD CONSTRAINT "run_result_segments_workout_result_id_run_results_workout_result_id_fk" FOREIGN KEY ("workout_result_id") REFERENCES "public"."run_results"("workout_result_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_result_segments" ADD CONSTRAINT "run_result_segments_prescription_step_id_run_prescription_steps_id_fk" FOREIGN KEY ("prescription_step_id") REFERENCES "public"."run_prescription_steps"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_results" ADD CONSTRAINT "run_results_workout_result_id_workout_results_id_fk" FOREIGN KEY ("workout_result_id") REFERENCES "public"."workout_results"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_exercise_prescriptions" ADD CONSTRAINT "strength_exercise_prescriptions_planned_workout_id_strength_prescriptions_planned_workout_id_fk" FOREIGN KEY ("planned_workout_id") REFERENCES "public"."strength_prescriptions"("planned_workout_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_exercise_prescriptions" ADD CONSTRAINT "strength_exercise_prescriptions_exercise_id_exercises_id_fk" FOREIGN KEY ("exercise_id") REFERENCES "public"."exercises"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_exercise_results" ADD CONSTRAINT "strength_exercise_results_workout_result_id_workout_results_id_fk" FOREIGN KEY ("workout_result_id") REFERENCES "public"."workout_results"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_exercise_results" ADD CONSTRAINT "strength_exercise_results_prescribed_exercise_id_strength_exercise_prescriptions_id_fk" FOREIGN KEY ("prescribed_exercise_id") REFERENCES "public"."strength_exercise_prescriptions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_exercise_results" ADD CONSTRAINT "strength_exercise_results_exercise_id_exercises_id_fk" FOREIGN KEY ("exercise_id") REFERENCES "public"."exercises"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_prescriptions" ADD CONSTRAINT "strength_prescriptions_planned_workout_id_planned_workouts_id_fk" FOREIGN KEY ("planned_workout_id") REFERENCES "public"."planned_workouts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_set_prescriptions" ADD CONSTRAINT "strength_set_prescriptions_exercise_prescription_id_strength_exercise_prescriptions_id_fk" FOREIGN KEY ("exercise_prescription_id") REFERENCES "public"."strength_exercise_prescriptions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_set_results" ADD CONSTRAINT "strength_set_results_exercise_result_id_strength_exercise_results_id_fk" FOREIGN KEY ("exercise_result_id") REFERENCES "public"."strength_exercise_results"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_set_results" ADD CONSTRAINT "strength_set_results_prescribed_set_id_strength_set_prescriptions_id_fk" FOREIGN KEY ("prescribed_set_id") REFERENCES "public"."strength_set_prescriptions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_substitution_options" ADD CONSTRAINT "strength_substitution_options_exercise_prescription_id_strength_exercise_prescriptions_id_fk" FOREIGN KEY ("exercise_prescription_id") REFERENCES "public"."strength_exercise_prescriptions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strength_substitution_options" ADD CONSTRAINT "strength_substitution_options_substitute_exercise_id_exercises_id_fk" FOREIGN KEY ("substitute_exercise_id") REFERENCES "public"."exercises"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "training_blocks" ADD CONSTRAINT "training_blocks_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_results" ADD CONSTRAINT "workout_results_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_results" ADD CONSTRAINT "workout_results_planned_workout_id_planned_workouts_id_fk" FOREIGN KEY ("planned_workout_id") REFERENCES "public"."planned_workouts"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "action_proposals" ADD CONSTRAINT "action_proposals_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "action_proposals" ADD CONSTRAINT "action_proposals_thread_id_coach_threads_id_fk" FOREIGN KEY ("thread_id") REFERENCES "public"."coach_threads"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "action_proposals" ADD CONSTRAINT "action_proposals_message_id_coach_messages_id_fk" FOREIGN KEY ("message_id") REFERENCES "public"."coach_messages"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "action_proposals" ADD CONSTRAINT "action_proposals_base_plan_version_id_plan_versions_id_fk" FOREIGN KEY ("base_plan_version_id") REFERENCES "public"."plan_versions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "action_proposals" ADD CONSTRAINT "action_proposals_applied_plan_version_id_plan_versions_id_fk" FOREIGN KEY ("applied_plan_version_id") REFERENCES "public"."plan_versions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ai_invocations" ADD CONSTRAINT "ai_invocations_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ai_invocations" ADD CONSTRAINT "ai_invocations_context_snapshot_id_intelligence_context_snapshots_id_fk" FOREIGN KEY ("context_snapshot_id") REFERENCES "public"."intelligence_context_snapshots"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "coach_messages" ADD CONSTRAINT "coach_messages_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "coach_messages" ADD CONSTRAINT "coach_messages_thread_id_coach_threads_id_fk" FOREIGN KEY ("thread_id") REFERENCES "public"."coach_threads"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "coach_messages" ADD CONSTRAINT "coach_messages_ai_invocation_id_ai_invocations_id_fk" FOREIGN KEY ("ai_invocation_id") REFERENCES "public"."ai_invocations"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "coach_threads" ADD CONSTRAINT "coach_threads_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "intelligence_context_snapshots" ADD CONSTRAINT "intelligence_context_snapshots_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "structured_decisions" ADD CONSTRAINT "structured_decisions_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "structured_decisions" ADD CONSTRAINT "structured_decisions_invocation_id_ai_invocations_id_fk" FOREIGN KEY ("invocation_id") REFERENCES "public"."ai_invocations"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "apple_notifications" ADD CONSTRAINT "apple_notifications_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "push_deliveries" ADD CONSTRAINT "push_deliveries_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "storekit_transactions" ADD CONSTRAINT "storekit_transactions_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "goals_owner_idx" ON "athlete_goals" USING btree ("athlete_id");--> statement-breakpoint
CREATE INDEX "baseline_owner_idx" ON "baseline_snapshots" USING btree ("athlete_id");--> statement-breakpoint
CREATE INDEX "change_sets_owner_idx" ON "plan_change_sets" USING btree ("athlete_id");--> statement-breakpoint
CREATE INDEX "plans_owner_idx" ON "plan_versions" USING btree ("athlete_id");--> statement-breakpoint
CREATE INDEX "planned_date_idx" ON "planned_workouts" USING btree ("plan_version_id","scheduled_date");--> statement-breakpoint
CREATE INDEX "context_owner_idx" ON "planning_context_snapshots" USING btree ("athlete_id");--> statement-breakpoint
CREATE INDEX "blocks_owner_idx" ON "training_blocks" USING btree ("athlete_id");--> statement-breakpoint
CREATE INDEX "results_owner_date_idx" ON "workout_results" USING btree ("athlete_id","training_date");--> statement-breakpoint
CREATE INDEX "proposals_owner_idx" ON "action_proposals" USING btree ("athlete_id");--> statement-breakpoint
CREATE INDEX "ai_quota_idx" ON "ai_invocations" USING btree ("athlete_id","created_at");--> statement-breakpoint
CREATE INDEX "coach_messages_thread_idx" ON "coach_messages" USING btree ("thread_id","created_at");--> statement-breakpoint
CREATE INDEX "coach_threads_owner_idx" ON "coach_threads" USING btree ("athlete_id");--> statement-breakpoint
CREATE INDEX "storekit_owner_idx" ON "storekit_transactions" USING btree ("athlete_id");--> statement-breakpoint
CREATE INDEX "storekit_original_idx" ON "storekit_transactions" USING btree ("original_transaction_id");--> statement-breakpoint
ALTER TABLE "athletes" ADD CONSTRAINT "athletes_auth_user_id_auth_user_id_fk" FOREIGN KEY ("auth_user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_installations" ADD CONSTRAINT "device_installations_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "entitlements" ADD CONSTRAINT "entitlements_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_sync_state" ADD CONSTRAINT "device_sync_state_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_sync_state" ADD CONSTRAINT "device_sync_state_device_id_athlete_id_device_installations_id_athlete_id_fk" FOREIGN KEY ("device_id","athlete_id") REFERENCES "public"."device_installations"("id","athlete_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sync_change_log" ADD CONSTRAINT "sync_change_log_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sync_mutations" ADD CONSTRAINT "sync_mutations_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sync_mutations" ADD CONSTRAINT "sync_mutations_device_id_athlete_id_device_installations_id_athlete_id_fk" FOREIGN KEY ("device_id","athlete_id") REFERENCES "public"."device_installations"("id","athlete_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "entitlements" ADD CONSTRAINT "entitlements_id_unique" UNIQUE("id");