CREATE TABLE "auth_account" (
	"id" text PRIMARY KEY NOT NULL,
	"account_id" text NOT NULL,
	"provider_id" text NOT NULL,
	"user_id" text NOT NULL,
	"access_token" text,
	"refresh_token" text,
	"id_token" text,
	"access_token_expires_at" timestamp with time zone,
	"refresh_token_expires_at" timestamp with time zone,
	"scope" text,
	"password" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "auth_session" (
	"id" text PRIMARY KEY NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"token" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"ip_address" text,
	"user_agent" text,
	"user_id" text NOT NULL,
	CONSTRAINT "auth_session_token_unique" UNIQUE("token")
);
--> statement-breakpoint
CREATE TABLE "auth_user" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"email" text NOT NULL,
	"email_verified" boolean DEFAULT false NOT NULL,
	"image" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "auth_user_email_unique" UNIQUE("email")
);
--> statement-breakpoint
CREATE TABLE "auth_verification" (
	"id" text PRIMARY KEY NOT NULL,
	"identifier" text NOT NULL,
	"value" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "athletes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"auth_user_id" text NOT NULL,
	"timezone" text DEFAULT 'UTC' NOT NULL,
	"locale" text DEFAULT 'en' NOT NULL,
	"distance_unit" text DEFAULT 'km' NOT NULL,
	"load_unit" text DEFAULT 'kg' NOT NULL,
	"week_starts_on" smallint DEFAULT 1 NOT NULL,
	"training_day_boundary" time,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "athletes_auth_user_id_unique" UNIQUE("auth_user_id"),
	CONSTRAINT "athletes_distance_unit" CHECK ("athletes"."distance_unit" in ('km', 'mi')),
	CONSTRAINT "athletes_load_unit" CHECK ("athletes"."load_unit" in ('kg', 'lb')),
	CONSTRAINT "athletes_week_starts_on" CHECK ("athletes"."week_starts_on" between 1 and 7),
	CONSTRAINT "athletes_revision_positive" CHECK ("athletes"."revision" > 0)
);
--> statement-breakpoint
CREATE TABLE "device_installations" (
	"id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"platform" text DEFAULT 'ios' NOT NULL,
	"app_version" text NOT NULL,
	"os_version" text,
	"push_token" text,
	"push_enabled" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"revoked_at" timestamp with time zone,
	CONSTRAINT "devices_id_athlete_unique" UNIQUE("id","athlete_id"),
	CONSTRAINT "devices_platform" CHECK ("device_installations"."platform" = 'ios')
);
--> statement-breakpoint
CREATE TABLE "entitlements" (
	"athlete_id" uuid NOT NULL,
	"entitlement_key" text NOT NULL,
	"status" text NOT NULL,
	"valid_until" timestamp with time zone,
	"source" text NOT NULL,
	"revision" bigint DEFAULT 1 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "entitlements_athlete_id_entitlement_key_pk" PRIMARY KEY("athlete_id","entitlement_key"),
	CONSTRAINT "entitlements_status" CHECK ("entitlements"."status" in ('active', 'grace', 'expired', 'revoked'))
);
--> statement-breakpoint
CREATE TABLE "training_policy_versions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"version" integer NOT NULL,
	"schema_version" integer NOT NULL,
	"status" text DEFAULT 'draft' NOT NULL,
	"config" jsonb NOT NULL,
	"checksum" text NOT NULL,
	"minimum_app_version" text,
	"published_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "training_policy_versions_version_unique" UNIQUE("version"),
	CONSTRAINT "policy_status" CHECK ("training_policy_versions"."status" in ('draft', 'published', 'retired')),
	CONSTRAINT "policy_versions_positive" CHECK ("training_policy_versions"."version" > 0 and "training_policy_versions"."schema_version" > 0)
);
--> statement-breakpoint
CREATE TABLE "device_sync_state" (
	"device_id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"last_pulled_sequence" bigint DEFAULT 0 NOT NULL,
	"last_push_at" timestamp with time zone,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sync_change_log" (
	"sequence" bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "sync_change_log_sequence_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1),
	"athlete_id" uuid NOT NULL,
	"entity_type" text NOT NULL,
	"entity_id" uuid NOT NULL,
	"operation" text NOT NULL,
	"row_revision" bigint,
	"changed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "sync_change_operation" CHECK ("sync_change_log"."operation" in ('upsert', 'delete'))
);
--> statement-breakpoint
CREATE TABLE "sync_mutations" (
	"client_mutation_id" uuid PRIMARY KEY NOT NULL,
	"athlete_id" uuid NOT NULL,
	"device_id" uuid NOT NULL,
	"entity_type" text NOT NULL,
	"entity_id" uuid NOT NULL,
	"operation" text NOT NULL,
	"request_hash" text NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL,
	"status" text NOT NULL,
	"result" jsonb,
	CONSTRAINT "sync_mutations_status" CHECK ("sync_mutations"."status" in ('applied', 'conflict', 'rejected')),
	CONSTRAINT "sync_mutations_operation" CHECK ("sync_mutations"."operation" in ('create', 'update', 'delete', 'activate_plan'))
);
--> statement-breakpoint
ALTER TABLE "auth_account" ADD CONSTRAINT "auth_account_user_id_auth_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "auth_session" ADD CONSTRAINT "auth_session_user_id_auth_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."auth_user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "athletes" ADD CONSTRAINT "athletes_auth_user_id_auth_user_id_fk" FOREIGN KEY ("auth_user_id") REFERENCES "public"."auth_user"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_installations" ADD CONSTRAINT "device_installations_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "entitlements" ADD CONSTRAINT "entitlements_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_sync_state" ADD CONSTRAINT "device_sync_state_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_sync_state" ADD CONSTRAINT "device_sync_state_device_id_athlete_id_device_installations_id_athlete_id_fk" FOREIGN KEY ("device_id","athlete_id") REFERENCES "public"."device_installations"("id","athlete_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sync_change_log" ADD CONSTRAINT "sync_change_log_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sync_mutations" ADD CONSTRAINT "sync_mutations_athlete_id_athletes_id_fk" FOREIGN KEY ("athlete_id") REFERENCES "public"."athletes"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sync_mutations" ADD CONSTRAINT "sync_mutations_device_id_athlete_id_device_installations_id_athlete_id_fk" FOREIGN KEY ("device_id","athlete_id") REFERENCES "public"."device_installations"("id","athlete_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "auth_account_user_idx" ON "auth_account" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "auth_session_user_idx" ON "auth_session" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "auth_verification_identifier_idx" ON "auth_verification" USING btree ("identifier");--> statement-breakpoint
CREATE INDEX "devices_athlete_idx" ON "device_installations" USING btree ("athlete_id");--> statement-breakpoint
CREATE INDEX "sync_changes_athlete_sequence_idx" ON "sync_change_log" USING btree ("athlete_id","sequence");--> statement-breakpoint
CREATE INDEX "sync_mutations_athlete_idx" ON "sync_mutations" USING btree ("athlete_id");