import {
  boolean,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import { athletes } from "./foundation";
import { workoutResults } from "./training";

export const stravaConnections = pgTable("strava_connections", {
  athleteId: uuid("athlete_id")
    .primaryKey()
    .references(() => athletes.id, { onDelete: "cascade" }),
  remoteId: text("remote_id").notNull().unique(),
  generation: uuid("generation").notNull(),
  tokens: text("tokens"),
  scopes: jsonb("scopes").$type<string[]>().notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  status: text("status").notNull(),
  autoPublish: boolean("auto_publish").notNull().default(false),
  connectedAt: timestamp("connected_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  history: jsonb("history"),
  historyExpiresAt: timestamp("history_expires_at", { withTimezone: true }),
});
export const stravaOauthStates = pgTable("strava_oauth_states", {
  digest: text("digest").primaryKey(),
  athleteId: uuid("athlete_id")
    .notNull()
    .references(() => athletes.id, { onDelete: "cascade" }),
  autoPublish: boolean("auto_publish").notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
});
export const stravaJobs = pgTable(
  "strava_jobs",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    athleteId: uuid("athlete_id")
      .notNull()
      .references(() => athletes.id, { onDelete: "cascade" }),
    generation: uuid("generation").notNull(),
    kind: text("kind").notNull(),
    logicalWorkoutId: uuid("logical_workout_id"),
    workoutId: uuid("workout_id").references(() => workoutResults.id, {
      onDelete: "cascade",
    }),
    state: text("state").notNull().default("queued"),
    attempts: integer("attempts").notNull().default(0),
    availableAt: timestamp("available_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    payload: jsonb("payload"),
    remoteId: text("remote_id"),
    errorCode: text("error_code"),
  },
  (t) => [
    uniqueIndex("strava_export_workout_idx").on(t.workoutId),
    uniqueIndex("strava_export_logical_idx").on(
      t.athleteId,
      t.logicalWorkoutId,
    ),
    index("strava_jobs_queue_idx").on(t.state, t.availableAt),
    index("strava_jobs_owner_idx").on(t.athleteId),
  ],
);
export const stravaWebhookReceipts = pgTable("strava_webhook_receipts", {
  digest: text("digest").primaryKey(),
  athleteId: uuid("athlete_id")
    .notNull()
    .references(() => athletes.id, { onDelete: "cascade" }),
  receivedAt: timestamp("received_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});
// Survives local account deletion only until the provider grant is revoked.
export const stravaRevocations = pgTable("strava_revocations", {
  owner: uuid("owner").primaryKey(),
  tokens: text("tokens").notNull(),
  attempts: integer("attempts").notNull().default(0),
  availableAt: timestamp("available_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});
// One application-wide request budget, shared by HTTP OAuth and background jobs.
export const stravaBudget = pgTable("strava_budget", {
  id: integer("id").primaryKey(),
  shortStart: timestamp("short_start", { withTimezone: true }).notNull(),
  shortCount: integer("short_count").notNull(),
  dayStart: timestamp("day_start", { withTimezone: true }).notNull(),
  dayCount: integer("day_count").notNull(),
  blockedUntil: timestamp("blocked_until", { withTimezone: true }),
});
