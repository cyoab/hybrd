CREATE TABLE "athlete_details" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"schema_version" integer NOT NULL,
	"details" jsonb NOT NULL,
	"provenance" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "athlete_details_athlete_id_unique" UNIQUE("athlete_id")
);
--> statement-breakpoint
CREATE TABLE "onboarding_requests" (
	"athlete_id" uuid NOT NULL,
	"route" text NOT NULL,
	"key" uuid NOT NULL,
	"fingerprint" text NOT NULL,
	"outcome" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "onboarding_requests_athlete_id_route_key_pk" PRIMARY KEY("athlete_id","route","key")
);
--> statement-breakpoint
CREATE TABLE "onboarding_states" (
	"athlete_id" uuid PRIMARY KEY NOT NULL,
	"draft" jsonb,
	"revision" bigint DEFAULT 1 NOT NULL,
	"athlete_revision" text NOT NULL,
	"step" text NOT NULL,
	"completion" jsonb,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "strava_connections" ADD COLUMN "onboarding_preview" jsonb;--> statement-breakpoint
ALTER TABLE "athlete_training_preferences" ADD COLUMN "onboarding" jsonb;--> statement-breakpoint
ALTER TABLE "baseline_snapshots" ADD COLUMN "provenance" jsonb DEFAULT '[]'::jsonb NOT NULL;--> statement-breakpoint
ALTER TABLE "athlete_details" ADD CONSTRAINT "athlete_details_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "onboarding_requests" ADD CONSTRAINT "onboarding_requests_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "onboarding_states" ADD CONSTRAINT "onboarding_states_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000010','ez-curl-bar','EZ curl bar') ON CONFLICT (id) DO NOTHING;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000011','weight-plates','Weight plates') ON CONFLICT (id) DO NOTHING;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000012','leg-extension','Leg extension') ON CONFLICT (id) DO NOTHING;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000013','leg-curl','Leg curl') ON CONFLICT (id) DO NOTHING;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000014','chest-press','Chest press') ON CONFLICT (id) DO NOTHING;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000015','lat-pulldown','Lat pulldown') ON CONFLICT (id) DO NOTHING;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000016','seated-row','Seated row') ON CONFLICT (id) DO NOTHING;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000017','smith-machine','Smith machine') ON CONFLICT (id) DO NOTHING;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000018','medicine-ball','Medicine ball') ON CONFLICT (id) DO NOTHING;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000019','stability-ball','Stability ball') ON CONFLICT (id) DO NOTHING;
--> statement-breakpoint
INSERT INTO equipment (id,slug,name) VALUES ('10000000-0000-4000-8001-000000000020','foam-roller','Foam roller') ON CONFLICT (id) DO NOTHING;
