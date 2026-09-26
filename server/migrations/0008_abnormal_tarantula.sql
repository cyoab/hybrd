CREATE TABLE "agent_actions" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"run_id" uuid NOT NULL,
	"receipt" jsonb NOT NULL,
	"before" jsonb NOT NULL,
	"after" jsonb NOT NULL,
	"preference_before" jsonb,
	"preference_after" jsonb,
	"undo_key" uuid,
	"undo_hash" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "agent_actions_run_id_unique" UNIQUE("run_id")
);
--> statement-breakpoint
CREATE TABLE "agent_analysis_packets" (
	"result_id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"result_revision" bigint NOT NULL,
	"packet" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "agent_device_challenges" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"run_id" uuid NOT NULL,
	"device_id" uuid NOT NULL,
	"challenge" jsonb NOT NULL,
	"ack_key" uuid,
	"ack_hash" text,
	CONSTRAINT "agent_device_challenges_run_id_unique" UNIQUE("run_id")
);
--> statement-breakpoint
CREATE TABLE "agent_device_manifests" (
	"device_id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"manifest" jsonb NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "agent_exercise_rules" (
	"athlete_id" uuid NOT NULL,
	"from_exercise_id" uuid NOT NULL,
	"to_exercise_id" uuid NOT NULL,
	"action_id" uuid NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	CONSTRAINT "agent_exercise_rules_athlete_id_from_exercise_id_pk" PRIMARY KEY("athlete_id","from_exercise_id")
);
--> statement-breakpoint
CREATE TABLE "agent_memory_settings" (
	"athlete_id" uuid PRIMARY KEY NOT NULL,
	"enabled" boolean DEFAULT false NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL
);
--> statement-breakpoint
ALTER TABLE "agent_runs" ADD COLUMN "api_version" integer DEFAULT 1 NOT NULL;--> statement-breakpoint
ALTER TABLE "agent_runs" ADD COLUMN "user_message_id" uuid;--> statement-breakpoint
ALTER TABLE "athlete_memories" ADD COLUMN "source_run_id" uuid;--> statement-breakpoint
ALTER TABLE "athlete_memories" ADD COLUMN "source_message_id" uuid;--> statement-breakpoint
ALTER TABLE "athlete_memories" ADD COLUMN "source_quote" text;--> statement-breakpoint
ALTER TABLE "athlete_memories" ADD COLUMN "confidence" jsonb;--> statement-breakpoint
ALTER TABLE "agent_actions" ADD CONSTRAINT "agent_actions_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_actions" ADD CONSTRAINT "agent_actions_run_id_agent_runs_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."agent_runs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_analysis_packets" ADD CONSTRAINT "agent_analysis_packets_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_device_challenges" ADD CONSTRAINT "agent_device_challenges_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_device_challenges" ADD CONSTRAINT "agent_device_challenges_run_id_agent_runs_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."agent_runs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_device_manifests" ADD CONSTRAINT "agent_device_manifests_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_exercise_rules" ADD CONSTRAINT "agent_exercise_rules_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_memory_settings" ADD CONSTRAINT "agent_memory_settings_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;