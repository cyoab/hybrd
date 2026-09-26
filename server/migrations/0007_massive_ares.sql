CREATE TABLE "agent_context_epochs" (
	"athlete_id" uuid PRIMARY KEY NOT NULL,
	"reset_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "agent_events" (
	"run_id" uuid NOT NULL,
	"sequence" bigint NOT NULL,
	"type" text NOT NULL,
	"data" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "agent_events_run_id_sequence_pk" PRIMARY KEY("run_id","sequence")
);
--> statement-breakpoint
CREATE TABLE "agent_runs" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"thread_id" uuid NOT NULL,
	"device_id" uuid NOT NULL,
	"idempotency_key" uuid NOT NULL,
	"request_hash" text NOT NULL,
	"task" text NOT NULL,
	"request" jsonb,
	"status" text DEFAULT 'queued' NOT NULL,
	"checkpoint" jsonb,
	"artifact" jsonb,
	"error_code" text,
	"lease_token" uuid,
	"lease_expires_at" timestamp with time zone,
	"provider_pending" boolean DEFAULT false NOT NULL,
	"invocation_id" uuid,
	"generative_calls" integer DEFAULT 0 NOT NULL,
	"event_sequence" bigint DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "agent_run_request_unique" UNIQUE("athlete_id","idempotency_key")
);
--> statement-breakpoint
CREATE TABLE "athlete_memories" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"category" text NOT NULL,
	"content" text NOT NULL,
	"source" text DEFAULT 'athlete' NOT NULL,
	"expires_at" timestamp with time zone,
	"revision" bigint DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "ai_invocations" ADD COLUMN "cached_input_tokens" integer;--> statement-breakpoint
ALTER TABLE "ai_invocations" ADD COLUMN "cache_write_tokens" integer;--> statement-breakpoint
ALTER TABLE "ai_invocations" ADD COLUMN "reasoning_tokens" integer;--> statement-breakpoint
ALTER TABLE "agent_context_epochs" ADD CONSTRAINT "agent_context_epochs_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_events" ADD CONSTRAINT "agent_events_run_id_agent_runs_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."agent_runs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_runs" ADD CONSTRAINT "agent_runs_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_runs" ADD CONSTRAINT "agent_runs_thread_id_coach_threads_id_fk" FOREIGN KEY ("thread_id") REFERENCES "public"."coach_threads"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "athlete_memories" ADD CONSTRAINT "athlete_memories_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "agent_run_queue_idx" ON "agent_runs" USING btree ("status","updated_at");--> statement-breakpoint
CREATE INDEX "agent_run_owner_idx" ON "agent_runs" USING btree ("athlete_id","thread_id");--> statement-breakpoint
CREATE INDEX "athlete_memory_owner_idx" ON "athlete_memories" USING btree ("athlete_id");