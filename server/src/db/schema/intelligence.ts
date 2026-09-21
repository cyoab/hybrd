import { sql } from "drizzle-orm";
import {
  bigint,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  unique,
  uuid,
} from "drizzle-orm/pg-core";
import { athletes } from "./foundation";
import { planVersions } from "./training";

const owner = () =>
  uuid("athlete_id")
    .notNull()
    .references(() => athletes.id, { onDelete: "cascade" });
const instant = (name: string) => timestamp(name, { withTimezone: true });
const created = () => instant("created_at").notNull().defaultNow();
const mutable = () => ({
  createdAt: created(),
  updatedAt: instant("updated_at").notNull().defaultNow(),
  revision: bigint("revision", { mode: "bigint" }).notNull().default(sql`1`),
  deletedAt: instant("deleted_at"),
});
export const intelligenceContextSnapshots = pgTable(
  "intelligence_context_snapshots",
  {
    id: uuid("id").primaryKey(),
    athleteId: owner(),
    contextType: text("context_type").notNull(),
    schemaVersion: integer("schema_version").notNull(),
    features: jsonb("features").notNull(),
    checksum: text("checksum").notNull(),
    retentionClass: text("retention_class").notNull(),
    createdAt: created(),
  },
);
export const aiInvocations = pgTable(
  "ai_invocations",
  {
    id: uuid("id").primaryKey(),
    athleteId: owner(),
    idempotencyKey: uuid("idempotency_key").notNull(),
    kind: text("kind").notNull(),
    scopeId: uuid("scope_id"),
    provider: text("provider").notNull(),
    model: text("model").notNull(),
    feature: text("feature").notNull(),
    promptVersion: text("prompt_version").notNull(),
    contextSnapshotId: uuid("context_snapshot_id").references(
      () => intelligenceContextSnapshots.id,
    ),
    requestHash: text("request_hash").notNull(),
    inputTokens: integer("input_tokens"),
    outputTokens: integer("output_tokens"),
    costUsdMicros: bigint("cost_usd_micros", { mode: "bigint" }),
    latencyMs: integer("latency_ms"),
    status: text("status").notNull(),
    providerRequestId: text("provider_request_id"),
    response: jsonb("response"),
    errorCode: text("error_code"),
    createdAt: created(),
    finishedAt: instant("finished_at"),
  },
  (t) => [
    unique("ai_request_unique").on(t.athleteId, t.idempotencyKey),
    index("ai_quota_idx").on(t.athleteId, t.createdAt),
  ],
);
export const structuredDecisions = pgTable("structured_decisions", {
  id: uuid("id").primaryKey(),
  athleteId: owner(),
  invocationId: uuid("invocation_id")
    .notNull()
    .references(() => aiInvocations.id, { onDelete: "cascade" }),
  decisionType: text("decision_type").notNull(),
  selectedChoice: text("selected_choice").notNull(),
  result: jsonb("result").notNull(),
  createdAt: created(),
});
export const coachThreads = pgTable(
  "coach_threads",
  {
    id: uuid("id").primaryKey(),
    athleteId: owner(),
    title: text("title"),
    ...mutable(),
  },
  (t) => [index("coach_threads_owner_idx").on(t.athleteId)],
);
export const coachMessages = pgTable(
  "coach_messages",
  {
    id: uuid("id").primaryKey(),
    athleteId: owner(),
    threadId: uuid("thread_id")
      .notNull()
      .references(() => coachThreads.id, { onDelete: "cascade" }),
    role: text("role").notNull(),
    content: text("content").notNull(),
    aiInvocationId: uuid("ai_invocation_id").references(() => aiInvocations.id),
    ...mutable(),
  },
  (t) => [index("coach_messages_thread_idx").on(t.threadId, t.createdAt)],
);
export const actionProposals = pgTable(
  "action_proposals",
  {
    id: uuid("id").primaryKey(),
    athleteId: owner(),
    threadId: uuid("thread_id").references(() => coachThreads.id, {
      onDelete: "cascade",
    }),
    messageId: uuid("message_id").references(() => coachMessages.id, {
      onDelete: "cascade",
    }),
    basePlanVersionId: uuid("base_plan_version_id").references(
      () => planVersions.id,
    ),
    actionType: text("action_type").notNull(),
    actionPayload: jsonb("action_payload").notNull(),
    rationale: text("rationale").notNull(),
    status: text("status").notNull().default("pending"),
    expiresAt: instant("expires_at").notNull(),
    acceptedAt: instant("accepted_at"),
    appliedPlanVersionId: uuid("applied_plan_version_id").references(
      () => planVersions.id,
    ),
    ...mutable(),
  },
  (t) => [index("proposals_owner_idx").on(t.athleteId)],
);
