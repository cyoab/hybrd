import { sql } from "drizzle-orm";
import {
  bigint,
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
const instant = (name: string) => timestamp(name, { withTimezone: true });
export const athleteDetails = pgTable("athlete_details", {
  id: uuid("id").primaryKey(),
  athleteId: owner().unique(),
  schemaVersion: integer("schema_version").notNull(),
  details: jsonb("details").notNull(),
  provenance: jsonb("provenance").notNull().default([]),
  createdAt: instant("created_at").notNull().defaultNow(),
  updatedAt: instant("updated_at").notNull().defaultNow(),
  revision: bigint("revision", { mode: "bigint" }).notNull().default(sql`1`),
  deletedAt: instant("deleted_at"),
});
export const onboardingStates = pgTable("onboarding_states", {
  athleteId: owner().primaryKey(),
  draft: jsonb("draft"),
  revision: bigint("revision", { mode: "bigint" }).notNull().default(sql`1`),
  athleteRevision: text("athlete_revision").notNull(),
  step: text("step").notNull(),
  completion: jsonb("completion"),
  updatedAt: instant("updated_at").notNull().defaultNow(),
});
export const onboardingRequests = pgTable(
  "onboarding_requests",
  {
    athleteId: owner(),
    route: text("route").notNull(),
    key: uuid("key").notNull(),
    fingerprint: text("fingerprint").notNull(),
    outcome: jsonb("outcome").notNull(),
    createdAt: instant("created_at").notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.athleteId, t.route, t.key] })],
);
