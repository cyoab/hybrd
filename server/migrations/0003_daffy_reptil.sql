CREATE TABLE "progress_activity" (
	"athlete_id" uuid NOT NULL,
	"result_id" uuid NOT NULL,
	"date" date NOT NULL,
	"payload" jsonb NOT NULL,
	CONSTRAINT "progress_activity_athlete_id_result_id_pk" PRIMARY KEY("athlete_id","result_id")
);
--> statement-breakpoint
CREATE TABLE "progress_cache" (
	"athlete_id" uuid NOT NULL,
	"key" text NOT NULL,
	"etag" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"payload" jsonb NOT NULL,
	CONSTRAINT "progress_cache_athlete_id_key_pk" PRIMARY KEY("athlete_id","key")
);
--> statement-breakpoint
CREATE TABLE "progress_comparisons" (
	"athlete_id" uuid NOT NULL,
	"key" text NOT NULL,
	"payload" jsonb NOT NULL,
	CONSTRAINT "progress_comparisons_athlete_id_key_pk" PRIMARY KEY("athlete_id","key")
);
--> statement-breakpoint
CREATE TABLE "progress_days" (
	"athlete_id" uuid NOT NULL,
	"date" date NOT NULL,
	"totals" jsonb NOT NULL,
	CONSTRAINT "progress_days_athlete_id_date_pk" PRIMARY KEY("athlete_id","date")
);
--> statement-breakpoint
CREATE TABLE "progress_outbox" (
	"athlete_id" uuid PRIMARY KEY NOT NULL,
	"sequence" bigint NOT NULL
);
--> statement-breakpoint
CREATE TABLE "progress_state" (
	"athlete_id" uuid PRIMARY KEY NOT NULL,
	"sequence" bigint NOT NULL,
	"rules_version" integer NOT NULL,
	"generation" uuid NOT NULL,
	"projected_at" timestamp with time zone NOT NULL,
	"refresh_after" timestamp with time zone,
	"metadata" jsonb NOT NULL
);
--> statement-breakpoint
ALTER TABLE "strength_set_results" ADD COLUMN "load_convention" text DEFAULT 'external' NOT NULL;--> statement-breakpoint
ALTER TABLE "workout_results" ADD COLUMN "date_basis" text DEFAULT 'performedDate' NOT NULL;--> statement-breakpoint
ALTER TABLE "workout_results" ADD COLUMN "logged_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "workout_results" ADD COLUMN "duration_s" integer;--> statement-breakpoint
ALTER TABLE "progress_activity" ADD CONSTRAINT "progress_activity_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "progress_cache" ADD CONSTRAINT "progress_cache_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "progress_comparisons" ADD CONSTRAINT "progress_comparisons_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "progress_days" ADD CONSTRAINT "progress_days_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "progress_outbox" ADD CONSTRAINT "progress_outbox_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "progress_state" ADD CONSTRAINT "progress_state_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "progress_activity_page_idx" ON "progress_activity" USING btree ("athlete_id","date","result_id");--> statement-breakpoint
ALTER TABLE "strength_set_results" ADD CONSTRAINT "actual_load_convention" CHECK ("strength_set_results"."load_convention" in ('external', 'bodyweight', 'assistance'));--> statement-breakpoint
ALTER TABLE "workout_results" ADD CONSTRAINT "result_date_basis" CHECK ("workout_results"."date_basis" in ('performedDate', 'loggedDate'));--> statement-breakpoint
ALTER TABLE "workout_results" ADD CONSTRAINT "result_duration" CHECK ("workout_results"."duration_s" is null or "workout_results"."duration_s" between 0 and 604800);