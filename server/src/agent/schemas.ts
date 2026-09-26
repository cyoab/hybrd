import { z } from "@hono/zod-openapi";
import { CursorSchema } from "../api/schemas";

export const AgentTask = z.enum([
  "chat",
  "analyze_workout",
  "create_plan",
  "modify_plan",
]);
export const AgentRunInput = z
  .object({
    schemaVersion: z.literal(1),
    deviceId: z.string().uuid(),
    threadId: z.string().uuid().nullable().default(null),
    task: AgentTask,
    message: z.string().trim().min(1).max(4000),
    workoutResultId: z.string().uuid().nullable().default(null),
    expectedWorkoutRevision: CursorSchema.nullable().default(null),
  })
  .strict()
  .superRefine((v, ctx) => {
    if (
      (v.task === "analyze_workout") !==
        Boolean(v.workoutResultId && v.expectedWorkoutRevision) ||
      (v.task !== "analyze_workout" &&
        (v.workoutResultId || v.expectedWorkoutRevision))
    )
      ctx.addIssue({
        code: "custom",
        message:
          "Analysis requires a result and expected revision; other tasks omit them.",
      });
  })
  .openapi("AgentRunInput");
export type RunInput = z.infer<typeof AgentRunInput>;
export const AgentStatus = z.enum([
  "queued",
  "running",
  "succeeded",
  "failed",
  "cancelled",
  "indeterminate",
]);
export const ScopeDecision = z
  .object({
    choice: z.enum([
      "hybrid_training",
      "training_safety",
      "mixed",
      "out_of_scope",
      "needs_clarification",
    ]),
    confidence: z.number().min(0).max(1),
  })
  .strict();
export type Scope = z.infer<typeof ScopeDecision>;
export const AgentAnswer = z
  .object({
    content: z.string().min(1).max(6000),
    observations: z
      .array(
        z
          .object({
            text: z.string().min(1).max(1000),
            metricRefs: z.array(z.string().min(1).max(200)).min(1).max(12),
          })
          .strict(),
      )
      .max(15),
    interpretations: z
      .array(
        z
          .object({
            text: z.string().min(1).max(1000),
            evidenceIds: z.array(z.string().min(1).max(80)).max(4),
          })
          .strict(),
      )
      .max(10),
    limitations: z.array(z.string().min(1).max(500)).max(12),
    recommendations: z.array(z.string().min(1).max(1000)).max(8),
    evidenceIds: z.array(z.string().min(1).max(80)).max(8),
  })
  .strict();
export type Answer = z.infer<typeof AgentAnswer>;
export const Citation = z
  .object({
    id: z.string(),
    version: z.literal(1),
    title: z.string(),
    url: z.string().url(),
    claim: z.string(),
    limitations: z.string(),
  })
  .strict()
  .openapi("AgentCitation");
export const AgentArtifact = AgentAnswer.omit({ evidenceIds: true })
  .extend({
    schemaVersion: z.literal(1),
    kind: z.enum([
      "answer",
      "workout_analysis",
      "scope_redirect",
      "clarification",
    ]),
    citations: z.array(Citation),
    analyzedResult: z
      .object({ id: z.string().uuid(), revision: CursorSchema })
      .nullable(),
  })
  .openapi("AgentArtifact");
export const AgentRun = z
  .object({
    id: z.string().uuid(),
    threadId: z.string().uuid(),
    schemaVersion: z.literal(1),
    task: AgentTask,
    status: AgentStatus,
    lastEventId: CursorSchema,
    artifact: AgentArtifact.nullable(),
    errorCode: z.string().nullable(),
    artifactStale: z.boolean(),
    createdAt: z.string().datetime(),
    updatedAt: z.string().datetime(),
  })
  .openapi("AgentRun");
export const AgentCapabilities = z
  .object({
    schemaVersion: z.literal(1),
    enabled: z.boolean(),
    configured: z.boolean(),
    tasks: z.object({
      chat: z.boolean(),
      analyze_workout: z.boolean(),
      create_plan: z.literal(false),
      modify_plan: z.literal(false),
    }),
    transport: z.literal("sse"),
    memory: z.literal("manual"),
    requiresConsent: z.literal(true),
    requiredEntitlement: z.string(),
    maxGenerativeCalls: z.number().int(),
    eventRetentionDays: z.literal(7),
  })
  .openapi("AgentCapabilities");
export const AgentEvent = z
  .object({
    id: CursorSchema,
    runId: z.string().uuid(),
    type: z.enum([
      "status",
      "tool_status",
      "artifact_ready",
      "completed",
      "failed",
      "cancelled",
    ]),
    data: z
      .object({
        status: AgentStatus.optional(),
        tool: z.string().optional(),
        errorCode: z.string().optional(),
      })
      .strict(),
    createdAt: z.string().datetime(),
  })
  .openapi("AgentEvent");
export const MemoryInput = z
  .object({
    expectedRevision: CursorSchema.nullable(),
    category: z.enum([
      "training_preference",
      "communication",
      "temporary_constraint",
    ]),
    content: z.string().trim().min(1).max(500),
    expiresAt: z.string().datetime().nullable(),
  })
  .strict()
  .openapi("AgentMemoryInput");
export const AgentMemory = MemoryInput.omit({ expectedRevision: true })
  .extend({
    id: z.string().uuid(),
    revision: CursorSchema,
    source: z.literal("athlete"),
    createdAt: z.string().datetime(),
    updatedAt: z.string().datetime(),
  })
  .openapi("AgentMemory");

export const terminal = (status: unknown) =>
  ["succeeded", "failed", "cancelled", "indeterminate"].includes(
    String(status),
  );
