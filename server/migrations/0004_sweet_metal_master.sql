CREATE TABLE "auth_otp_throttle" (
	"key" text PRIMARY KEY NOT NULL,
	"window_start" timestamp with time zone NOT NULL,
	"last_sent_at" timestamp with time zone NOT NULL,
	"send_count" integer NOT NULL
);
--> statement-breakpoint
DROP INDEX "auth_verification_identifier_idx";--> statement-breakpoint
CREATE INDEX "auth_otp_throttle_window_idx" ON "auth_otp_throttle" USING btree ("window_start");--> statement-breakpoint
CREATE UNIQUE INDEX "auth_account_provider_identity_idx" ON "auth_account" USING btree ("provider_id","account_id");--> statement-breakpoint
-- Verification records are ephemeral. Retain only the newest challenge before
-- enforcing one usable challenge per identifier; never delete users/sessions.
WITH ranked AS (
  SELECT id, row_number() OVER (PARTITION BY identifier ORDER BY created_at DESC, id DESC) AS position
  FROM auth_verification
)
DELETE FROM auth_verification WHERE id IN (SELECT id FROM ranked WHERE position > 1);
--> statement-breakpoint
CREATE UNIQUE INDEX "auth_verification_identifier_idx" ON "auth_verification" USING btree ("identifier");
