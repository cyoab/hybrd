CREATE TABLE "strava_budget" (
	"id" integer PRIMARY KEY NOT NULL,
	"short_start" timestamp with time zone NOT NULL,
	"short_count" integer NOT NULL,
	"day_start" timestamp with time zone NOT NULL,
	"day_count" integer NOT NULL,
	"blocked_until" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "strava_connections" (
	"athlete_id" uuid PRIMARY KEY NOT NULL,
	"remote_id" text NOT NULL,
	"generation" uuid NOT NULL,
	"tokens" text,
	"scopes" jsonb NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"status" text NOT NULL,
	"auto_publish" boolean DEFAULT false NOT NULL,
	"connected_at" timestamp with time zone DEFAULT now() NOT NULL,
	"history" jsonb,
	"history_expires_at" timestamp with time zone,
	CONSTRAINT "strava_connections_remote_id_unique" UNIQUE("remote_id")
);
--> statement-breakpoint
CREATE TABLE "strava_jobs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"athlete_id" uuid NOT NULL,
	"generation" uuid NOT NULL,
	"kind" text NOT NULL,
	"logical_workout_id" uuid,
	"workout_id" uuid,
	"state" text DEFAULT 'queued' NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"available_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"payload" jsonb,
	"remote_id" text,
	"error_code" text
);
--> statement-breakpoint
CREATE TABLE "strava_oauth_states" (
	"digest" text PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"auto_publish" boolean NOT NULL,
	"expires_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "strava_revocations" (
	"owner" uuid PRIMARY KEY NOT NULL,
	"tokens" text NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"available_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "strava_webhook_receipts" (
	"digest" text PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "strava_connections" ADD CONSTRAINT "strava_connections_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strava_jobs" ADD CONSTRAINT "strava_jobs_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strava_jobs" ADD CONSTRAINT "strava_jobs_workout_id_workout_results_id_fk" FOREIGN KEY ("workout_id") REFERENCES "public"."workout_results"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strava_oauth_states" ADD CONSTRAINT "strava_oauth_states_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "strava_webhook_receipts" ADD CONSTRAINT "strava_webhook_receipts_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "strava_export_workout_idx" ON "strava_jobs" USING btree ("workout_id");--> statement-breakpoint
CREATE UNIQUE INDEX "strava_export_logical_idx" ON "strava_jobs" USING btree ("athlete_id","logical_workout_id");--> statement-breakpoint
CREATE INDEX "strava_jobs_queue_idx" ON "strava_jobs" USING btree ("state","available_at");--> statement-breakpoint
CREATE INDEX "strava_jobs_owner_idx" ON "strava_jobs" USING btree ("athlete_id");