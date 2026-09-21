import type postgres from "postgres";
import { ApiError } from "../api/errors";
import { effectiveEntitlements } from "../billing/entitlements";
import type { Env } from "../config/env";
import { PolicyConfigSchema } from "../config/policy";
import {
  emit,
  ensureInitialChange,
  hash,
  insertRow,
  owned,
  type Row,
  type Tx,
  updateRow,
  wire,
  withAthlete,
} from "../db/store";
import { readEntity } from "../domain/read";
import {
  type DecisionRequest,
  DecisionRequestSchema,
  decisionDefinition,
} from "./jev/decision-registry";
import type { CoachContext, IntelligenceProvider, Usage } from "./provider";
import {
  type ChatRequest,
  ChatRequestSchema,
  ChatResponseSchema,
  CoachOutputSchema,
  DecisionOutputSchema,
  DecisionResponseSchema,
} from "./schemas";

async function activePlan(sql: Tx, athleteId: string, id: string) {
  const p = await owned(sql, "plan_versions", id, athleteId),
    b = await owned(
      sql,
      "training_blocks",
      String(p.training_block_id),
      athleteId,
    );
  if (b.active_plan_version_id !== id || b.status !== "active")
    throw new ApiError(
      409,
      "PLAN_HEAD_CONFLICT",
      "Refresh context from the current active plan.",
    );
  return { plan: p, block: b };
}
export function intelligenceServices(
  client: postgres.Sql,
  env: Env,
  provider: IntelligenceProvider,
) {
  async function execute(
    authUserId: string,
    key: string,
    kind: "decision" | "chat",
    request: DecisionRequest | ChatRequest,
  ) {
    const fingerprint = hash({ kind, request });
    const reservation = await withAthlete(
      client,
      authUserId,
      async (sql, athlete) => {
        const athleteId = String(athlete.id);
        await ensureInitialChange(sql, athlete);
        const [prior] =
          await sql`select * from ai_invocations where athlete_id=${athleteId} and idempotency_key=${key}`;
        if (prior) {
          if (prior.request_hash !== fingerprint)
            throw new ApiError(
              409,
              "IDEMPOTENCY_KEY_REUSED",
              "Use a new request key for different content.",
            );
          if (prior.status === "completed") {
            if (!prior.response)
              throw new ApiError(
                409,
                "IDEMPOTENCY_EXPIRED",
                "The cached response expired; retrieve canonical records through sync.",
              );
            return { cached: prior.response as Row };
          }
          if (prior.status === "pending")
            throw new ApiError(
              409,
              Date.now() - new Date(prior.created_at).getTime() > 60000
                ? "AI_REQUEST_INDETERMINATE"
                : "AI_REQUEST_IN_PROGRESS",
              "This request is pending or its provider outcome is uncertain. It will not be charged again with the same key.",
            );
          throw new ApiError(
            502,
            String(prior.error_code ?? "PROVIDER_UNAVAILABLE"),
            "This attempt failed. A new key is required for a new attempt.",
          );
        }
        if (!athlete.cloud_ai_consent)
          throw new ApiError(
            403,
            "AI_CONSENT_REQUIRED",
            "Enable cloud intelligence consent before sending training context.",
          );
        const entitlements = await effectiveEntitlements(sql, athleteId);
        if (
          !entitlements.some(
            (e) =>
              e.key === env.AI_REQUIRED_ENTITLEMENT &&
              ["active", "grace"].includes(e.status),
          )
        )
          throw new ApiError(
            403,
            "ENTITLEMENT_REQUIRED",
            "An active coaching entitlement is required.",
          );
        if (!provider.available(kind))
          throw new ApiError(
            503,
            "INTELLIGENCE_NOT_CONFIGURED",
            "The intelligence provider is not configured.",
          );
        const [policy] =
          await sql`select * from training_policy_versions where status='published' order by version desc limit 1`;
        const config = PolicyConfigSchema.safeParse(policy?.config);
        if (
          !policy ||
          !config.success ||
          !(kind === "decision"
            ? config.data.features.remoteDecisions
            : config.data.features.remoteCoach)
        )
          throw new ApiError(
            503,
            "FEATURE_DISABLED",
            "This intelligence feature is disabled by policy.",
          );
        const [quota] =
          await sql`select count(*) filter(where kind=${kind} and created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC')::int as daily,count(*) filter(where created_at>now()-interval '1 minute')::int as recent,count(*) filter(where status='pending' and created_at>now()-interval '1 minute')::int as pending from ai_invocations where athlete_id=${athleteId} and created_at>now()-interval '1 day'`;
        if (
          Number(quota?.daily) >=
            (kind === "decision"
              ? env.AI_DECISIONS_PER_DAY
              : env.AI_CHATS_PER_DAY) ||
          Number(quota?.recent) >= env.AI_REQUESTS_PER_MINUTE ||
          Number(quota?.pending) >= 2
        )
          throw new ApiError(
            429,
            "AI_QUOTA_EXCEEDED",
            "The cloud intelligence request limit has been reached.",
          );
        let context: Row = request.context,
          coach: CoachContext | undefined;
        if (kind === "chat") {
          const chat = request as ChatRequest;
          await owned(sql, "coach_threads", chat.threadId, athleteId);
          const [pending] =
            await sql`select id from ai_invocations where athlete_id=${athleteId} and scope_id=${chat.threadId} and status='pending' and created_at>now()-interval '1 minute'`;
          if (pending)
            throw new ApiError(
              409,
              "THREAD_BUSY",
              "Wait for the previous coach response before continuing this conversation.",
            );
          const workouts: Row[] = [];
          if (chat.context.activePlanVersionId) {
            await activePlan(sql, athleteId, chat.context.activePlanVersionId);
            const plan = await readEntity(
              sql,
              athleteId,
              "plan_version",
              chat.context.activePlanVersionId,
            );
            for (const id of chat.context.relevantLogicalWorkoutIds) {
              const workout = ((plan?.workouts ?? []) as Row[]).find(
                (w) => w.logicalWorkoutId === id,
              );
              if (!workout)
                throw new ApiError(
                  400,
                  "INVALID_CONTEXT",
                  "A context workout is outside the active plan.",
                );
              workouts.push(workout);
            }
          } else if (chat.context.relevantLogicalWorkoutIds.length)
            throw new ApiError(
              400,
              "INVALID_CONTEXT",
              "Workout context requires an active plan.",
            );
          context = { ...chat.context, relevantWorkouts: workouts };
          if (JSON.stringify(context).length > 32000)
            throw new ApiError(
              400,
              "CONTEXT_TOO_LARGE",
              "Send fewer relevant workouts.",
            );
          const historyRows =
            await sql`select role,content from coach_messages where thread_id=${chat.threadId} and athlete_id=${athleteId} and deleted_at is null order by created_at desc,id desc limit 12`;
          let remaining = 16000;
          const history: CoachContext["history"] = [];
          for (const row of historyRows) {
            if (remaining < row.content.length) break;
            remaining -= row.content.length;
            history.unshift({ role: row.role, content: row.content });
          }
          coach = { context, history, message: chat.message };
        }
        const id = crypto.randomUUID(),
          snapshotId = crypto.randomUUID();
        // Store compact client features only; canonical prescriptions are already versioned.
        await insertRow(sql, "intelligence_context_snapshots", {
          id: snapshotId,
          athleteId,
          contextType: kind,
          schemaVersion: 1,
          features: request.context,
          checksum: hash(request.context),
          retentionClass: "30_days",
        });
        await insertRow(sql, "ai_invocations", {
          id,
          athleteId,
          idempotencyKey: key,
          kind,
          scopeId: kind === "chat" ? (request as ChatRequest).threadId : null,
          provider: "openrouter",
          model:
            kind === "decision"
              ? env.OPENROUTER_JEV_MODEL
              : (env.OPENROUTER_LLM_MODEL ?? "test-provider"),
          feature:
            kind === "decision"
              ? (request as DecisionRequest).decisionType
              : "coach",
          promptVersion: "1",
          contextSnapshotId: snapshotId,
          requestHash: fingerprint,
          status: "pending",
        });
        return {
          id,
          athleteId,
          policyVersion: Number(policy.version),
          config: config.data,
          coach,
        };
      },
    );
    if ("cached" in reservation) return reservation.cached;
    const started = performance.now();
    try {
      const coach = reservation.coach;
      if (kind === "chat" && !coach)
        throw new Error("Missing reserved coach context");
      const supplied =
        kind === "decision"
          ? await provider.decision(request as DecisionRequest)
          : await provider.chat(coach as CoachContext);
      return await withAthlete(client, authUserId, async (sql, athlete) => {
        if (!athlete.cloud_ai_consent)
          throw new ApiError(
            403,
            "AI_CONSENT_REQUIRED",
            "Cloud intelligence consent was withdrawn while the request was running.",
          );
        let response: Row;
        if (kind === "decision") {
          const input = request as DecisionRequest,
            result = DecisionOutputSchema.parse(supplied.result),
            allowed = Object.keys(decisionDefinition(input).criteria);
          if (
            !allowed.includes(result.decision) ||
            result.alternatives.some((a) => !allowed.includes(a.choice))
          )
            throw new ApiError(
              502,
              "INVALID_PROVIDER_RESPONSE",
              "Unsupported decision choice.",
            );
          const decisionId = crypto.randomUUID(),
            thresholds = reservation.config.intelligence.jevConfidence;
          response = {
            ...result,
            decisionId,
            policyVersion: reservation.policyVersion,
            disposition:
              result.confidence >= thresholds.auto
                ? "eligible"
                : result.confidence >= thresholds.review
                  ? "review"
                  : "abstain",
          };
          await insertRow(sql, "structured_decisions", {
            id: decisionId,
            athleteId: reservation.athleteId,
            invocationId: reservation.id,
            decisionType: input.decisionType,
            selectedChoice: result.decision,
            result: response,
          });
          await emit(
            sql,
            reservation.athleteId,
            "structured_decision",
            decisionId,
            "upsert",
            null,
          );
        } else {
          const input = request as ChatRequest,
            result = CoachOutputSchema.parse(supplied.result);
          await owned(
            sql,
            "coach_threads",
            input.threadId,
            reservation.athleteId,
          );
          const [newer] =
            await sql`select id from ai_invocations where scope_id=${input.threadId} and athlete_id=${reservation.athleteId} and created_at>(select created_at from ai_invocations where id=${reservation.id}) limit 1`;
          if (newer)
            throw new ApiError(
              409,
              "THREAD_CHANGED",
              "A newer request superseded this response.",
            );
          if (input.context.activePlanVersionId)
            await activePlan(
              sql,
              reservation.athleteId,
              input.context.activePlanVersionId,
            );
          const messageId = crypto.randomUUID();
          for (const [role, content, id] of [
            ["user", input.message, crypto.randomUUID()],
            ["assistant", result.content, messageId],
          ]) {
            await insertRow(sql, "coach_messages", {
              id,
              athleteId: reservation.athleteId,
              threadId: input.threadId,
              role,
              content,
              aiInvocationId: reservation.id,
            });
            await emit(
              sql,
              reservation.athleteId,
              "coach_message",
              String(id),
              "upsert",
              "1",
            );
          }
          const actionProposals: Row[] = [];
          for (const draft of result.actionProposals) {
            const base = input.context.activePlanVersionId;
            if (!base)
              throw new ApiError(
                502,
                "INVALID_PROVIDER_RESPONSE",
                "A proposal requires an active plan.",
              );
            const { block } = await activePlan(
              sql,
              reservation.athleteId,
              base,
            );
            if ("logicalWorkoutId" in draft.payload) {
              if (
                !input.context.relevantLogicalWorkoutIds.includes(
                  draft.payload.logicalWorkoutId,
                )
              )
                throw new ApiError(
                  502,
                  "INVALID_PROVIDER_RESPONSE",
                  "The proposal refers to a workout outside its context.",
                );
              const [completed] =
                await sql`select id from workout_results where athlete_id=${reservation.athleteId} and logical_workout_id=${draft.payload.logicalWorkoutId} and deleted_at is null limit 1`;
              if (completed)
                throw new ApiError(
                  502,
                  "INVALID_PROVIDER_RESPONSE",
                  "A proposal cannot change completed work.",
                );
            }
            if (
              draft.type === "move_workout" &&
              (draft.payload.targetDate < String(wire(block).startDate) ||
                draft.payload.targetDate > String(wire(block).endDate))
            )
              throw new ApiError(
                502,
                "INVALID_PROVIDER_RESPONSE",
                "A move must stay within the training block.",
              );
            if (draft.type === "substitute_exercise") {
              const [sub] =
                await sql`select o.substitute_exercise_id from strength_substitution_options o join strength_exercise_prescriptions e on e.id=o.exercise_prescription_id join planned_workouts w on w.id=e.planned_workout_id where w.plan_version_id=${base} and w.logical_workout_id=${draft.payload.logicalWorkoutId} and e.exercise_id=${draft.payload.exerciseId} and e.substitution_allowed=true and o.substitute_exercise_id=${draft.payload.replacementExerciseId}`;
              if (!sub)
                throw new ApiError(
                  502,
                  "INVALID_PROVIDER_RESPONSE",
                  "The proposed exercise is not an allowed substitution.",
                );
            }
            const id = crypto.randomUUID(),
              expiresAt = new Date(
                Date.now() +
                  reservation.config.intelligence.proposalExpiryHours * 3600000,
              );
            await insertRow(sql, "action_proposals", {
              id,
              athleteId: reservation.athleteId,
              threadId: input.threadId,
              messageId,
              basePlanVersionId: base,
              actionType: draft.type,
              actionPayload: draft.payload,
              rationale: draft.rationale,
              expiresAt,
            });
            await emit(
              sql,
              reservation.athleteId,
              "action_proposal",
              id,
              "upsert",
              "1",
            );
            actionProposals.push({
              id,
              ...draft,
              basePlanVersionId: base,
              expiresAt: expiresAt.toISOString(),
            });
          }
          response = {
            messageId,
            content: result.content,
            actionProposals,
            policyVersion: reservation.policyVersion,
          };
        }
        await finish(
          sql,
          reservation.id,
          supplied.usage,
          response,
          Math.round(performance.now() - started),
        );
        return response;
      });
    } catch (error) {
      const code =
        error instanceof ApiError ? error.code : "INVALID_PROVIDER_RESPONSE";
      // Account deletion may have removed the reservation; never recreate it.
      await client`update ai_invocations set status='failed',error_code=${code},finished_at=now(),latency_ms=${Math.round(performance.now() - started)} where id=${reservation.id} and status='pending'`;
      if (error instanceof ApiError) throw error;
      throw new ApiError(
        502,
        "INVALID_PROVIDER_RESPONSE",
        "The provider returned a response that could not be validated.",
      );
    }
  }
  return {
    decision: async (user: string, key: string, request: DecisionRequest) =>
      DecisionResponseSchema.parse(
        await execute(
          user,
          key,
          "decision",
          DecisionRequestSchema.parse(request),
        ),
      ),
    chat: async (user: string, key: string, request: ChatRequest) =>
      ChatResponseSchema.parse(
        await execute(user, key, "chat", ChatRequestSchema.parse(request)),
      ),
  };
}
async function finish(
  sql: Tx,
  id: string,
  usage: Usage,
  response: Row,
  latencyMs: number,
) {
  await updateRow(sql, "ai_invocations", id, {
    status: "completed",
    response,
    finishedAt: new Date(),
    latencyMs,
    inputTokens: usage.inputTokens ?? null,
    outputTokens: usage.outputTokens ?? null,
    costUsdMicros: usage.costUsdMicros ?? null,
    providerRequestId: usage.providerRequestId ?? null,
  });
}
