ALTER TABLE "agent_actions" ADD COLUMN "apply_key" uuid;--> statement-breakpoint
ALTER TABLE "agent_actions" ADD COLUMN "apply_hash" text;--> statement-breakpoint
ALTER TABLE "agent_actions" ADD COLUMN "authorization" jsonb;