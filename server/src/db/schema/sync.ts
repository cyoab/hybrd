import { sql } from "drizzle-orm";
import {
  bigint,
  check,
  foreignKey,
  index,
  jsonb,
  pgTable,
  text,
  timestamp,
  uuid,
} from "drizzle-orm/pg-core";
import { athletes, deviceInstallations } from "./foundation";

// Every mutation and its acknowledgement commit with the domain change.
export const syncMutations = pgTable(
  "sync_mutations",
  {
    clientMutationId: uuid("client_mutation_id").primaryKey(),
    athleteId: uuid("athlete_id")
      .notNull()
      .references(() => athletes.id, { onDelete: "cascade" }),
    deviceId: uuid("device_id").notNull(),
    entityType: text("entity_type").notNull(),
    entityId: uuid("entity_id").notNull(),
    operation: text("operation").notNull(),
    requestHash: text("request_hash").notNull(),
    receivedAt: timestamp("received_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    status: text("status").notNull(),
    result: jsonb("result").$type<Record<string, unknown>>(),
  },
  (t) => [
    index("sync_mutations_athlete_idx").on(t.athleteId),
    foreignKey({
      columns: [t.deviceId, t.athleteId],
      foreignColumns: [deviceInstallations.id, deviceInstallations.athleteId],
    }).onDelete("cascade"),
    check(
      "sync_mutations_status",
      sql`${t.status} in ('applied', 'conflict', 'rejected')`,
    ),
    check(
      "sync_mutations_operation",
      sql`${t.operation} in ('create', 'update', 'delete', 'activate_plan')`,
    ),
  ],
);

export const syncChangeLog = pgTable(
  "sync_change_log",
  {
    sequence: bigint("sequence", { mode: "bigint" })
      .primaryKey()
      .generatedAlwaysAsIdentity(),
    athleteId: uuid("athlete_id")
      .notNull()
      .references(() => athletes.id, { onDelete: "cascade" }),
    entityType: text("entity_type").notNull(),
    entityId: uuid("entity_id").notNull(),
    operation: text("operation").notNull(),
    rowRevision: bigint("row_revision", { mode: "bigint" }),
    changedAt: timestamp("changed_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (t) => [
    index("sync_changes_athlete_sequence_idx").on(t.athleteId, t.sequence),
    check("sync_change_operation", sql`${t.operation} in ('upsert', 'delete')`),
  ],
);

export const deviceSyncState = pgTable(
  "device_sync_state",
  {
    deviceId: uuid("device_id").primaryKey(),
    athleteId: uuid("athlete_id")
      .notNull()
      .references(() => athletes.id, { onDelete: "cascade" }),
    lastPulledSequence: bigint("last_pulled_sequence", { mode: "bigint" })
      .notNull()
      .default(sql`0`),
    lastPushAt: timestamp("last_push_at", { withTimezone: true }),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (t) => [
    foreignKey({
      columns: [t.deviceId, t.athleteId],
      foreignColumns: [deviceInstallations.id, deviceInstallations.athleteId],
    }).onDelete("cascade"),
  ],
);
