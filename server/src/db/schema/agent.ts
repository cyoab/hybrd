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
    apiVersion: integer("api_version").notNull().default(1),
    userMessageId: uuid("user_message_id"),
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
    sourceRunId: uuid("source_run_id"),
    sourceMessageId: uuid("source_message_id"),
    sourceQuote: text("source_quote"),
    confidence: jsonb("confidence"),
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

export const agentActions = pgTable("agent_actions", {
  id: uuid("id").primaryKey(),
  athleteId: owner(),
  runId: uuid("run_id")
    .notNull()
    .unique()
    .references(() => agentRuns.id, { onDelete: "cascade" }),
  receipt: jsonb("receipt").notNull(),
  before: jsonb("before").notNull(),
  after: jsonb("after").notNull(),
  preferenceBefore: jsonb("preference_before"),
  preferenceAfter: jsonb("preference_after"),
  applyKey: uuid("apply_key"),
  applyHash: text("apply_hash"),
  authorization: jsonb("authorization"),
  undoKey: uuid("undo_key"),
  undoHash: text("undo_hash"),
  createdAt: instant("created_at").notNull().defaultNow(),
});
export const agentExerciseRules = pgTable(
  "agent_exercise_rules",
  {
    athleteId: owner(),
    fromExerciseId: uuid("from_exercise_id").notNull(),
    toExerciseId: uuid("to_exercise_id").notNull(),
    actionId: uuid("action_id").notNull(),
    revision: bigint("revision", { mode: "bigint" }).notNull().default(sql`1`),
  },
  (t) => [primaryKey({ columns: [t.athleteId, t.fromExerciseId] })],
);
export const agentDeviceManifests = pgTable("agent_device_manifests", {
  deviceId: uuid("device_id").primaryKey(),
  athleteId: owner(),
  manifest: jsonb("manifest").notNull(),
  updatedAt: instant("updated_at").notNull().defaultNow(),
});
export const agentDeviceChallenges = pgTable("agent_device_challenges", {
  id: uuid("id").primaryKey(),
  athleteId: owner(),
  runId: uuid("run_id")
    .notNull()
    .unique()
    .references(() => agentRuns.id, { onDelete: "cascade" }),
  deviceId: uuid("device_id").notNull(),
  challenge: jsonb("challenge").notNull(),
  ackKey: uuid("ack_key"),
  ackHash: text("ack_hash"),
});
export const agentMemorySettings = pgTable("agent_memory_settings", {
  athleteId: owner().primaryKey(),
  enabled: boolean("enabled").notNull().default(false),
  revision: bigint("revision", { mode: "bigint" }).notNull().default(sql`1`),
});
export const agentAnalysisPackets = pgTable("agent_analysis_packets", {
  resultId: uuid("result_id").primaryKey(),
  athleteId: owner(),
  resultRevision: bigint("result_revision", { mode: "bigint" }).notNull(),
  packet: jsonb("packet").notNull(),
  createdAt: instant("created_at").notNull().defaultNow(),
});
