import type postgres from "postgres";
import { ApiError } from "../api/errors";
import { effectiveEntitlements } from "../billing/entitlements";
import type { Env } from "../config/env";
import { PolicyConfigSchema } from "../config/policy";
import {
  emit,
  hash,
  insertRow,
  owned,
  type Row,
  type Tx,
  wire,
  withAthlete,
} from "../db/store";
import type { AgentProvider, Message } from "./provider";
import {
  AgentArtifact,
  AgentCapabilities,
  AgentEvent,
  AgentMemory,
  AgentRun,
  AgentRunInput,
  type Answer,
  MemoryInput,
  type RunInput,
  terminal,
} from "./schemas";

export type Checkpoint = {
  stage: "classify" | "turn" | "review";
  messages: Message[];
  memoryHash: string;
  athleteRevision: string;
  refs: string[];
  revisions: Record<string, string>;
  evidenceIds: string[];
  answer?: Answer;
  toolCount: number;
  history: string;
};
function memoryView(row: Row) {
  const data = wire(row);
  delete data.athleteId;
  return AgentMemory.parse(data);
}
export async function event(sql: Tx, id: string, type: string, data: Row) {
  const [run] =
    await sql`update agent_runs set event_sequence=event_sequence+1,updated_at=now() where id=${id} returning event_sequence::text`;
  if (!run) return;
  await sql`insert into agent_events(run_id,sequence,type,data) values(${id},${run.event_sequence},${type},${sql.json(data as postgres.JSONValue)})`;
}
export async function gate(
  sql: Tx,
  athlete: Row,
  env: Env,
  provider: AgentProvider,
) {
  if (!env.AGENT_ENABLED)
    throw new ApiError(
      503,
      "AGENT_DISABLED",
      "The training agent is not enabled in this environment.",
    );
  if (!athlete.cloud_ai_consent)
    throw new ApiError(
      403,
      "AI_CONSENT_REQUIRED",
      "Cloud intelligence consent is required.",
    );
  const access = await effectiveEntitlements(sql, String(athlete.id));
  if (
    !access.some(
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
  if (!provider.available())
    throw new ApiError(
      503,
      "INTELLIGENCE_NOT_CONFIGURED",
      "Configure the agent model and scope classifier before starting runs.",
    );
  const [policy] =
    await sql`select config from training_policy_versions where status='published' order by version desc limit 1`;
  const parsed = PolicyConfigSchema.safeParse(policy?.config);
  if (!parsed.success || !parsed.data.features.remoteCoach)
    throw new ApiError(
      503,
      "FEATURE_DISABLED",
      "Cloud coaching is disabled by policy.",
    );
}
export async function device(sql: Tx, athleteId: string, id: string) {
  const [row] =
    await sql`select id from device_installations where id=${id} and athlete_id=${athleteId} and revoked_at is null`;
  if (!row)
    throw new ApiError(
      403,
      "DEVICE_UNAVAILABLE",
      "Register the current installation before starting an agent run.",
    );
}
export async function runView(sql: Tx, run: Row) {
  let artifactStale = false;
  if (run.artifact) {
    const artifact = AgentArtifact.parse(run.artifact);
    if (artifact.analyzedResult) {
      const [result] =
        await sql`select revision::text,deleted_at from workout_results where id=${artifact.analyzedResult.id} and athlete_id=${String(run.athlete_id)}`;
      artifactStale =
        !result ||
        Boolean(result.deleted_at) ||
        result.revision !== artifact.analyzedResult.revision;
    }
  }
  return AgentRun.parse({
    ...wire(run),
    schemaVersion: 1,
    lastEventId: String(run.event_sequence),
    artifactStale,
  });
}
export async function closeRun(
  sql: Tx,
  run: Row,
  status: "failed" | "cancelled" | "indeterminate",
  code: string,
) {
  if (terminal(run.status)) return;
  await sql`update agent_runs set status=${status},error_code=${code},checkpoint=null,lease_token=null,lease_expires_at=null where id=${String(run.id)}`;
  await event(
    sql,
    String(run.id),
    status === "cancelled" ? "cancelled" : "failed",
    { status, errorCode: code },
  );
}
async function resetMemoryContext(sql: Tx, athleteId: string) {
  await sql`insert into agent_context_epochs(athlete_id) values(${athleteId}) on conflict(athlete_id) do update set reset_at=now()`;
  const pending = await sql<
    Row[]
  >`select * from agent_runs where athlete_id=${athleteId} and status in ('queued','running')`;
  for (const run of pending)
    await closeRun(sql, run, "cancelled", "MEMORY_CONTEXT_CHANGED");
  // Cached transcripts must not retain forgotten material, including terminal attempts.
  await sql`update agent_runs set checkpoint=null where athlete_id=${athleteId}`;
}
export function agentServices(
  client: postgres.Sql,
  env: Env,
  provider: AgentProvider,
) {
  return {
    capabilities: async (authUserId: string) =>
      withAthlete(client, authUserId, async (sql) => {
        const [policy] =
          await sql`select config from training_policy_versions where status='published' order by version desc limit 1`;
        const p = PolicyConfigSchema.safeParse(policy?.config);
        const enabled =
          env.AGENT_ENABLED && p.success && p.data.features.remoteCoach;
        return AgentCapabilities.parse({
          schemaVersion: 1,
          enabled,
          configured: provider.available(),
          tasks: {
            chat: enabled && provider.available(),
            analyze_workout: enabled && provider.available(),
            create_plan: false,
            modify_plan: false,
          },
          transport: "sse",
          memory: "manual",
          requiresConsent: true,
          requiredEntitlement: env.AI_REQUIRED_ENTITLEMENT,
          maxGenerativeCalls: env.AGENT_MAX_GENERATIVE_CALLS,
          eventRetentionDays: 7,
        });
      }),
    create: async (authUserId: string, key: string, body: RunInput) =>
      withAthlete(client, authUserId, async (sql, athlete) => {
        const input = AgentRunInput.parse(body),
          athleteId = String(athlete.id),
          fingerprint = hash(input);
        await device(sql, athleteId, input.deviceId);
        const [prior] = await sql<
          Row[]
        >`select * from agent_runs where athlete_id=${athleteId} and idempotency_key=${key}`;
        if (prior) {
          if (prior.request_hash !== fingerprint)
            throw new ApiError(
              409,
              "IDEMPOTENCY_KEY_REUSED",
              "Use a new key for different content.",
            );
          return runView(sql, prior);
        }
        if (!["chat", "analyze_workout"].includes(input.task))
          throw new ApiError(
            409,
            "AGENT_TASK_NOT_ENABLED",
            "Plan creation and mutation are not enabled yet; check agent capabilities.",
          );
        await gate(sql, athlete, env, provider);
        const [quota] =
          await sql`select count(*) filter(where created_at >= date_trunc('day',now() at time zone 'UTC') at time zone 'UTC')::int as daily,count(*) filter(where created_at>now()-interval '1 minute')::int as recent,count(*) filter(where status in ('queued','running'))::int as pending from agent_runs where athlete_id=${athleteId}`;
        if (
          Number(quota?.daily) >= env.AI_CHATS_PER_DAY ||
          Number(quota?.recent) >= env.AI_REQUESTS_PER_MINUTE ||
          Number(quota?.pending) >= 2
        )
          throw new ApiError(
            429,
            "AI_QUOTA_EXCEEDED",
            "The agent request limit has been reached.",
          );
        if (input.workoutResultId) {
          const result = await owned(
            sql,
            "workout_results",
            input.workoutResultId,
            athleteId,
          );
          if (String(result.revision) !== input.expectedWorkoutRevision)
            throw new ApiError(
              409,
              "WORKOUT_REVISION_CONFLICT",
              "Refresh the workout before requesting analysis.",
            );
        }
        const threadId = input.threadId ?? crypto.randomUUID();
        if (input.threadId)
          await owned(sql, "coach_threads", threadId, athleteId);
        else {
          await insertRow(sql, "coach_threads", {
            id: threadId,
            athleteId,
            title: "Training coach",
          });
          await emit(sql, athleteId, "coach_thread", threadId, "upsert", "1");
        }
        const [busy] =
          await sql`select id from agent_runs where athlete_id=${athleteId} and thread_id=${threadId} and status in ('queued','running') union all select id from ai_invocations where athlete_id=${athleteId} and scope_id=${threadId} and kind='chat' and status='pending' limit 1`;
        if (busy)
          throw new ApiError(
            409,
            "THREAD_BUSY",
            "Wait for the current conversation run to finish.",
          );
        const id = crypto.randomUUID();
        await insertRow(sql, "agent_runs", {
          id,
          athleteId,
          threadId,
          deviceId: input.deviceId,
          idempotencyKey: key,
          requestHash: fingerprint,
          task: input.task,
          request: input,
        });
        const messageId = crypto.randomUUID();
        await insertRow(sql, "coach_messages", {
          id: messageId,
          athleteId,
          threadId,
          role: "user",
          content: input.message,
        });
        await emit(sql, athleteId, "coach_message", messageId, "upsert", "1");
        await event(sql, id, "status", { status: "queued" });
        return runView(sql, await owned(sql, "agent_runs", id, athleteId));
      }),
    get: async (authUserId: string, id: string) =>
      withAthlete(client, authUserId, async (sql, athlete) =>
        runView(sql, await owned(sql, "agent_runs", id, String(athlete.id))),
      ),
    events: async (authUserId: string, id: string, after: string) =>
      withAthlete(client, authUserId, async (sql, athlete) => {
        const run = await owned(sql, "agent_runs", id, String(athlete.id));
        if (BigInt(after) > BigInt(String(run.event_sequence)))
          throw new ApiError(
            409,
            "AGENT_EVENT_CURSOR_AHEAD",
            "The event cursor is ahead of this run.",
          );
        const [oldest] =
          await sql`select min(sequence)::text as sequence from agent_events where run_id=${id}`;
        if (
          BigInt(after) < BigInt(String(run.event_sequence)) &&
          (!oldest?.sequence || BigInt(after) + 1n < BigInt(oldest.sequence))
        )
          throw new ApiError(
            409,
            "AGENT_EVENT_REPLAY_EXPIRED",
            "Restore the run status; the requested progress history expired.",
          );
        const events = await sql<
          Row[]
        >`select * from agent_events where run_id=${id} and sequence>${after} order by sequence limit 100`;
        return {
          run: await runView(sql, run),
          events: events.map((e) =>
            AgentEvent.parse({ ...wire(e), id: String(e.sequence) }),
          ),
        };
      }),
    cancel: async (authUserId: string, id: string) =>
      withAthlete(client, authUserId, async (sql, athlete) => {
        const run = await owned(sql, "agent_runs", id, String(athlete.id));
        await closeRun(sql, run, "cancelled", "CANCELLED_BY_ATHLETE");
        return runView(
          sql,
          await owned(sql, "agent_runs", id, String(athlete.id)),
        );
      }),
    memories: async (authUserId: string) =>
      withAthlete(client, authUserId, async (sql, athlete) => ({
        memories: (
          await sql<
            Row[]
          >`select * from athlete_memories where athlete_id=${String(athlete.id)} order by id`
        ).map(memoryView),
      })),
    putMemory: async (authUserId: string, id: string, body: unknown) =>
      withAthlete(client, authUserId, async (sql, athlete) => {
        const input = MemoryInput.parse(body),
          athleteId = String(athlete.id);
        const [prior] = await sql<
          Row[]
        >`select * from athlete_memories where id=${id}`;
        if (prior && prior.athlete_id !== athleteId)
          throw new ApiError(
            404,
            "REFERENCE_UNAVAILABLE",
            "Memory unavailable.",
          );
        if ((prior ? String(prior.revision) : null) !== input.expectedRevision)
          throw new ApiError(
            409,
            "MEMORY_REVISION_CONFLICT",
            "Refresh memory before changing it.",
          );
        if (input.expiresAt && Date.parse(input.expiresAt) <= Date.now())
          throw new ApiError(
            400,
            "INVALID_MEMORY_EXPIRY",
            "A new memory must expire in the future.",
          );
        const [size] =
          await sql`select count(*)::int as n,coalesce(sum(length(content)),0)::int as chars from athlete_memories where athlete_id=${athleteId} and id<>${id}`;
        if (
          Number(size?.n) >= 20 ||
          Number(size?.chars) + input.content.length > 5000
        )
          throw new ApiError(
            400,
            "MEMORY_BUDGET_EXCEEDED",
            "Keep at most 20 memories and 5000 characters in total.",
          );
        await sql`insert into athlete_memories(id,athlete_id,category,content,expires_at) values(${id},${athleteId},${input.category},${input.content},${input.expiresAt}) on conflict(id) do update set category=excluded.category,content=excluded.content,expires_at=excluded.expires_at,revision=athlete_memories.revision+1,updated_at=now()`;
        await resetMemoryContext(sql, athleteId);
        return memoryView(await owned(sql, "athlete_memories", id, athleteId));
      }),
    forgetMemory: async (authUserId: string, id: string, revision: string) =>
      withAthlete(client, authUserId, async (sql, athlete) => {
        const memory = await owned(
          sql,
          "athlete_memories",
          id,
          String(athlete.id),
        );
        if (String(memory.revision) !== revision)
          throw new ApiError(
            409,
            "MEMORY_REVISION_CONFLICT",
            "Refresh memory before forgetting it.",
          );
        await sql`delete from athlete_memories where id=${id}`;
        await resetMemoryContext(sql, String(athlete.id));
      }),
  };
}
export async function exportAgent(sql: Tx, athleteId: string) {
  return {
    runs: (
      await sql<
        Row[]
      >`select id,thread_id,task,status,request,artifact,error_code,created_at,updated_at from agent_runs where athlete_id=${athleteId} order by created_at,id`
    ).map(wire),
    memories: (
      await sql<
        Row[]
      >`select * from athlete_memories where athlete_id=${athleteId} order by id`
    ).map(wire),
  };
}
