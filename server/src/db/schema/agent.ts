import { sql } from "drizzle-orm";
import {
  bigint,
  boolean,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  unique,
  uuid,
} from "drizzle-orm/pg-core";
import { athletes } from "./foundation";
import { coachThreads } from "./intelligence";

const owner = () =>
  uuid("athlete_id")
    .notNull()
    .references(() => athletes.id, { onDelete: "cascade" });
const instant = (name: string) => timestamp(name, { withTimezone: true });
export const agentRuns = pgTable(
  "agent_runs",
  {
    id: uuid("id").primaryKey(),
    athleteId: owner(),
    threadId: uuid("thread_id")
      .notNull()
      .references(() => coachThreads.id, { onDelete: "cascade" }),
    deviceId: uuid("device_id").notNull(),
    idempotencyKey: uuid("idempotency_key").notNull(),
    requestHash: text("request_hash").notNull(),
    task: text("task").notNull(),
    request: jsonb("request"),
    status: text("status").notNull().default("queued"),
    checkpoint: jsonb("checkpoint"),
    artifact: jsonb("artifact"),
    errorCode: text("error_code"),
    leaseToken: uuid("lease_token"),
    leaseExpiresAt: instant("lease_expires_at"),
    providerPending: boolean("provider_pending").notNull().default(false),
    invocationId: uuid("invocation_id"),
    generativeCalls: integer("generative_calls").notNull().default(0),
    eventSequence: bigint("event_sequence", { mode: "bigint" })
      .notNull()
      .default(sql`0`),
    createdAt: instant("created_at").notNull().defaultNow(),
    updatedAt: instant("updated_at").notNull().defaultNow(),
  },
  (t) => [
    unique("agent_run_request_unique").on(t.athleteId, t.idempotencyKey),
    index("agent_run_queue_idx").on(t.status, t.updatedAt),
    index("agent_run_owner_idx").on(t.athleteId, t.threadId),
  ],
);
export const agentEvents = pgTable(
  "agent_events",
  {
    runId: uuid("run_id")
      .notNull()
      .references(() => agentRuns.id, { onDelete: "cascade" }),
    sequence: bigint("sequence", { mode: "bigint" }).notNull(),
    type: text("type").notNull(),
    data: jsonb("data").notNull(),
    createdAt: instant("created_at").notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.runId, t.sequence] })],
);
export const athleteMemories = pgTable(
  "athlete_memories",
  {
    id: uuid("id").primaryKey(),
    athleteId: owner(),
    category: text("category").notNull(),
    content: text("content").notNull(),
    source: text("source").notNull().default("athlete"),
    expiresAt: instant("expires_at"),
    revision: bigint("revision", { mode: "bigint" }).notNull().default(sql`1`),
    createdAt: instant("created_at").notNull().defaultNow(),
    updatedAt: instant("updated_at").notNull().defaultNow(),
  },
  (t) => [index("athlete_memory_owner_idx").on(t.athleteId)],
);
export const agentContextEpochs = pgTable("agent_context_epochs", {
  athleteId: owner().primaryKey(),
  resetAt: instant("reset_at").notNull().defaultNow(),
});
