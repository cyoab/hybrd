import { sql } from "drizzle-orm";
import {
  bigint,
  date,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uuid,
} from "drizzle-orm/pg-core";
import { athletes } from "./foundation";

const owner = () =>
  uuid("athlete_id")
    .notNull()
    .references(() => athletes.id, { onDelete: "cascade" });
const sequence = () => bigint("sequence", { mode: "bigint" }).notNull();
// One durable, coalesced job per owner; the sequence advances in the sync transaction.
export const progressOutbox = pgTable("progress_outbox", {
  athleteId: owner().primaryKey(),
  sequence: sequence(),
});
export const progressState = pgTable("progress_state", {
  athleteId: owner().primaryKey(),
  sequence: sequence(),
  rulesVersion: integer("rules_version").notNull(),
  generation: uuid("generation").notNull(),
  projectedAt: timestamp("projected_at", { withTimezone: true }).notNull(),
  refreshAfter: timestamp("refresh_after", { withTimezone: true }),
  metadata: jsonb("metadata").notNull(),
});
export const progressDays = pgTable(
  "progress_days",
  {
    athleteId: owner(),
    date: date("date").notNull(),
    totals: jsonb("totals").notNull(),
  },
  (t) => [primaryKey({ columns: [t.athleteId, t.date] })],
);
export const progressActivity = pgTable(
  "progress_activity",
  {
    athleteId: owner(),
    resultId: uuid("result_id").notNull(),
    date: date("date").notNull(),
    payload: jsonb("payload").notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.athleteId, t.resultId] }),
    index("progress_activity_page_idx").on(t.athleteId, t.date, t.resultId),
  ],
);
export const progressComparisons = pgTable(
  "progress_comparisons",
  {
    athleteId: owner(),
    key: text("key").notNull(),
    payload: jsonb("payload").notNull(),
  },
  (t) => [primaryKey({ columns: [t.athleteId, t.key] })],
);
export const progressCache = pgTable(
  "progress_cache",
  {
    athleteId: owner(),
    key: text("key").notNull(),
    etag: text("etag").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .default(sql`now()`),
    payload: jsonb("payload").notNull(),
  },
  (t) => [primaryKey({ columns: [t.athleteId, t.key] })],
);
