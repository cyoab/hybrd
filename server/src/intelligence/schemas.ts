import { z } from "@hono/zod-openapi";
import { Day, Features, Id } from "../domain/schemas";
export const ChatRequestSchema = z
  .object({
    threadId: Id,
    message: z.string().trim().min(1).max(4000),
    context: z
      .object({
        schemaVersion: z.literal(1),
        activePlanVersionId: Id.nullable(),
        summary: z.string().max(4000),
        relevantLogicalWorkoutIds: z.array(Id).max(12).default([]),
        recentFeatures: Features.default({}),
      })
      .strict(),
  })
  .strict()
  .openapi("CoachRequest");
export const ProposalDraftSchema = z
  .discriminatedUnion("type", [
    z
      .object({
        type: z.literal("move_workout"),
        payload: z.object({ logicalWorkoutId: Id, targetDate: Day }).strict(),
        rationale: z.string().min(1).max(2000),
      })
      .strict(),
    z
      .object({
        type: z.literal("substitute_exercise"),
        payload: z
          .object({
            logicalWorkoutId: Id,
            exerciseId: Id,
            replacementExerciseId: Id,
          })
          .strict(),
        rationale: z.string().min(1).max(2000),
      })
      .strict(),
    z
      .object({
        type: z.literal("replan_block"),
        payload: z
          .object({
            objective: z.enum([
              "reduce_load",
              "change_schedule",
              "rebalance_priorities",
            ]),
          })
          .strict(),
        rationale: z.string().min(1).max(2000),
      })
      .strict(),
  ])
  .openapi("CoachProposalDraft");
export const CoachOutputSchema = z
  .object({
    content: z.string().min(1).max(8000),
    actionProposals: z.array(ProposalDraftSchema).max(3),
  })
  .strict();
export const DecisionOutputSchema = z
  .object({
    decision: z.string(),
    confidence: z.number().min(0).max(1),
    alternatives: z
      .array(
        z.object({ choice: z.string(), confidence: z.number().min(0).max(1) }),
      )
      .max(20),
  })
  .strict();
export const DecisionResponseSchema = DecisionOutputSchema.extend({
  decisionId: Id,
  policyVersion: z.number().int(),
  disposition: z.enum(["eligible", "review", "abstain"]),
}).openapi("DecisionResponse");
export const ChatResponseSchema = z
  .object({
    messageId: Id,
    content: z.string(),
    actionProposals: z.array(
      z.discriminatedUnion("type", [
        ProposalDraftSchema.options[0].safeExtend({
          id: Id,
          basePlanVersionId: Id,
          expiresAt: z.string().datetime(),
        }),
        ProposalDraftSchema.options[1].safeExtend({
          id: Id,
          basePlanVersionId: Id,
          expiresAt: z.string().datetime(),
        }),
        ProposalDraftSchema.options[2].safeExtend({
          id: Id,
          basePlanVersionId: Id,
          expiresAt: z.string().datetime(),
        }),
      ]),
    ),
    policyVersion: z.number().int(),
  })
  .openapi("CoachResponse");
export type ChatRequest = z.infer<typeof ChatRequestSchema>;
export type CoachOutput = z.infer<typeof CoachOutputSchema>;
export type DecisionOutput = z.infer<typeof DecisionOutputSchema>;
