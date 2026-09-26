import type postgres from "postgres";
import type { Env } from "../config/env";
import { hash, owned, type Row, type Tx, wire, withAthlete } from "../db/store";
import { applyDraft, undoAction } from "./actions";
import { acknowledgeChallenge, putAnalysisPacket } from "./enrichment";
import {
  assertScope,
  canonicalWorkouts,
  fail,
  manifestFor,
  planningState,
} from "./planning";
import type { AgentProvider } from "./provider";
import { closeRun, device, resetMemoryContext } from "./service";
import {
  ActionReceipt,
  AgentRunInputV2,
  AgentRunV2,
  type AnyInput,
  DeviceChallenge,
  DeviceManifest,
  LearnedMemory,
  MemorySettings,
} from "./v2-schemas";
import { AckInput, AgentCapabilitiesV2, ClaimInput } from "./v2-wire";

export async function runViewV2(sql: Tx, run: Row) {
  const [action] =
    await sql`select receipt from agent_actions where run_id=${String(run.id)}`;
  const [challenge] =
    await sql`select challenge from agent_device_challenges where run_id=${String(run.id)}`;
  const learned =
    await sql`select id from athlete_memories where source_run_id=${String(run.id)} order by id`;
  const c = challenge ? DeviceChallenge.parse(challenge.challenge) : null;
  if (
    (c?.status === "pending" || c?.status === "claimed") &&
    Date.parse(c.expiresAt) <= Date.now()
  )
    c.status = c.status === "claimed" ? "indeterminate" : "expired";
  const a = action ? ActionReceipt.parse(action.receipt) : null;
  if (a && Date.parse(a.undoExpiresAt) <= Date.now()) a.undoAvailable = false;
  let artifactStale = false;
  const artifact = run.artifact as {
    analyzedResult?: { id: string; revision: string };
  } | null;
  if (artifact?.analyzedResult) {
    const [r] =
      await sql`select revision::text,deleted_at from workout_results where id=${artifact.analyzedResult.id} and athlete_id=${String(run.athlete_id)}`;
    artifactStale =
      !r ||
      Boolean(r.deleted_at) ||
      r.revision !== artifact.analyzedResult.revision;
  }
  return AgentRunV2.parse({
    ...wire(run),
    schemaVersion: 2,
    lastEventId: String(run.event_sequence),
    artifactStale,
    action: a,
    deviceChallenge: c,
    learnedMemoryIds: learned.map((m) => m.id),
  });
}
export function v2Services(
  client: postgres.Sql,
  env: Env,
  _provider: AgentProvider,
  base: {
    create: (auth: string, key: string, body: AnyInput) => Promise<unknown>;
    capabilities: (
      auth: string,
    ) => Promise<{ enabled: boolean; configured: boolean }>;
  },
) {
  return {
    removeRuleV2: async (auth: string, id: string, revision: string) =>
      withAthlete(client, auth, async (sql, a) => {
        const [rule] =
          await sql`select revision::text from agent_exercise_rules where athlete_id=${String(a.id)} and from_exercise_id=${id}`;
        if (!rule)
          fail(
            "EXERCISE_RULE_UNAVAILABLE",
            "This recurring rule is unavailable.",
          );
        if (rule.revision !== revision)
          fail(
            "PREFERENCE_REVISION_CONFLICT",
            "Refresh the recurring rule before removing it.",
          );
        await sql`delete from agent_exercise_rules where athlete_id=${String(a.id)} and from_exercise_id=${id}`;
        return { removed: true };
      }),
    claimChallengeV2: async (
      auth: string,
      id: string,
      key: string,
      body: unknown,
    ) =>
      withAthlete(client, auth, async (sql, a) => {
        const input = ClaimInput.parse(body),
          row = await owned(sql, "agent_device_challenges", id, String(a.id)),
          c = DeviceChallenge.parse(row.challenge),
          raw = row.challenge as Row;
        if (raw.claimKey) {
          if (raw.claimKey !== key || raw.claimHash !== hash(input))
            fail(
              "DEVICE_CLAIM_CONFLICT",
              "This challenge has already been claimed.",
            );
          if (c.status === "claimed" && Date.parse(c.expiresAt) <= Date.now())
            c.status = "indeterminate";
          return c;
        }
        await manifestFor(sql, String(a.id), input.deviceId);
        if (
          c.scope.deviceId !== input.deviceId ||
          c.scope.recordingId !== input.recordingId ||
          c.digest !== input.digest
        )
          fail(
            "DEVICE_CHALLENGE_MISMATCH",
            "Device, recording and exact action digest must match.",
          );
        if (Date.parse(c.expiresAt) <= Date.now())
          fail("DEVICE_CHALLENGE_EXPIRED", "This challenge expired.");
        if (c.status !== "pending")
          fail("DEVICE_CLAIM_CONFLICT", "This challenge is no longer pending.");
        c.status = "claimed";
        c.claimToken = crypto.randomUUID();
        await sql`update agent_device_challenges set challenge=${sql.json({ ...c, claimKey: key, claimHash: hash(input) })} where id=${id}`;
        return c;
      }),
    cancelChallengeV2: async (auth: string, id: string) =>
      withAthlete(client, auth, async (sql, a) => {
        const row = await owned(
            sql,
            "agent_device_challenges",
            id,
            String(a.id),
          ),
          c = DeviceChallenge.parse(row.challenge);
        if (c.status === "pending") {
          c.status =
            Date.parse(c.expiresAt) <= Date.now() ? "expired" : "rejected";
          c.result = {
            localState: c.scope.expectedLocalState,
            reason: "Cancelled by athlete",
          };
          await sql`update agent_device_challenges set challenge=${sql.json(c)} where id=${id}`;
        }
        return c;
      }),
    capabilitiesV2: async (auth: string) => {
      const c = await base.capabilities(auth);
      return AgentCapabilitiesV2.parse({
        schemaVersion: 2,
        supportedSchemaVersions: [1, 2],
        enabled: c.enabled,
        configured: c.configured,
        tasks: {
          chat: c.enabled && c.configured,
          analyze_workout: c.enabled && c.configured,
          create_plan: c.enabled && c.configured,
          modify_plan: c.enabled && c.configured,
          device_action: c.enabled && c.configured,
        },
        transport: "sse",
        memory: "opt_in_learning",
        requiresConsent: true,
        requiredEntitlement: env.AI_REQUIRED_ENTITLEMENT,
        maxGenerativeCalls: env.AGENT_MAX_GENERATIVE_CALLS,
        eventRetentionDays: 7,
        executableVersion: 2,
        prescriptionSchemaVersion: 1,
      });
    },
    createV2: async (auth: string, key: string, body: unknown) => {
      const input = AgentRunInputV2.parse(body);
      await base.create(auth, key, input);
      return withAthlete(client, auth, async (sql, athlete) => {
        const [run] = await sql<
          Row[]
        >`select * from agent_runs where athlete_id=${String(athlete.id)} and idempotency_key=${key}`;
        return runViewV2(sql, run!);
      });
    },
    getV2: async (auth: string, id: string) =>
      withAthlete(client, auth, async (sql, a) =>
        runViewV2(sql, await owned(sql, "agent_runs", id, String(a.id))),
      ),
    lookupV2: async (auth: string, key: string, cancel = false) =>
      withAthlete(client, auth, async (sql, a) => {
        const [run] = await sql<
          Row[]
        >`select * from agent_runs where athlete_id=${String(a.id)} and idempotency_key=${key}`;
        if (!run)
          fail(
            "AGENT_REQUEST_NOT_FOUND",
            "No run exists for this key; lookup never creates billable work.",
          );
        if (cancel)
          await closeRun(sql, run, "cancelled", "CANCELLED_BY_ATHLETE");
        return runViewV2(
          sql,
          await owned(sql, "agent_runs", String(run.id), String(a.id)),
        );
      }),
    listV2: async (auth: string, before: string | null) =>
      withAthlete(client, auth, async (sql, a) => {
        let boundary: Row | undefined;
        if (before)
          boundary = await owned(sql, "agent_runs", before, String(a.id));
        const rows = boundary
          ? await sql<
              Row[]
            >`select * from agent_runs where athlete_id=${String(a.id)} and (created_at,id)<(${boundary.created_at as Date},${before!}::uuid) order by created_at desc,id desc limit 21`
          : await sql<
              Row[]
            >`select * from agent_runs where athlete_id=${String(a.id)} order by created_at desc,id desc limit 21`;
        return {
          runs: await Promise.all(
            rows.slice(0, 20).map((r) => runViewV2(sql, r)),
          ),
          nextBefore: rows.length > 20 ? String(rows[19]!.id) : null,
        };
      }),
    contextV2: async (auth: string, blockId: string | null) =>
      withAthlete(client, auth, async (sql, a) => {
        const s = await planningState(sql, a);
        return {
          contextToken: s.contextToken,
          profileRevision: s.profileRevision,
          timezone: String(a.timezone),
          trainingDayBoundary: a.training_day_boundary ?? "00:00:00",
          blocks: s.blocks.map((b) => ({
            id: b.id,
            activePlanVersionId: b.active_plan_version_id,
            revision: String(b.revision),
            startDate: wire(b).startDate,
            endDate: wire(b).endDate,
          })),
          exerciseRules: s.rules.map(wire),
          workouts: blockId
            ? await canonicalWorkouts(
                sql,
                String(a.id),
                String(
                  (await owned(sql, "training_blocks", blockId, String(a.id)))
                    .active_plan_version_id,
                ),
              )
            : [],
        };
      }),
    putManifest: async (auth: string, body: unknown) =>
      withAthlete(client, auth, async (sql, a) => {
        const m = DeviceManifest.parse(body);
        await device(sql, String(a.id), m.deviceId);
        if (m.pairedDeviceId) {
          if (m.pairedDeviceId === m.deviceId)
            fail("DEVICE_PAIR_INVALID", "Pair distinct installations.");
          await device(sql, String(a.id), m.pairedDeviceId);
        }
        await sql`insert into agent_device_manifests(device_id,athlete_id,manifest) values(${m.deviceId},${String(a.id)},${sql.json(m)}) on conflict(device_id) do update set manifest=excluded.manifest,updated_at=now()`;
        return {
          manifest: m,
          expiresAt: new Date(Date.now() + 86400000).toISOString(),
        };
      }),
    applyV2: async (auth: string, id: string, key: string, body: unknown) =>
      withAthlete(client, auth, (sql, a) => applyDraft(sql, a, id, key, body)),
    undoV2: async (auth: string, id: string, key: string, body: unknown) =>
      withAthlete(client, auth, (sql, a) => undoAction(sql, a, id, key, body)),
    packetV2: async (auth: string, body: unknown) =>
      withAthlete(client, auth, (sql, a) => putAnalysisPacket(sql, a, body)),
    ackV2: async (auth: string, id: string, key: string, body: unknown) =>
      withAthlete(client, auth, (sql, a) =>
        acknowledgeChallenge(sql, a, id, key, AckInput.parse(body)),
      ),
    settingsV2: async (auth: string, body?: unknown) =>
      withAthlete(client, auth, async (sql, a) => {
        const athleteId = String(a.id);
        await sql`insert into agent_memory_settings(athlete_id) values(${athleteId}) on conflict do nothing`;
        let [s] =
          await sql`select enabled,revision::text from agent_memory_settings where athlete_id=${athleteId}`;
        if (body !== undefined) {
          const input = MemorySettings.parse(body);
          if (s!.revision !== input.expectedRevision)
            fail("MEMORY_REVISION_CONFLICT", "Refresh memory settings.");
          [s] =
            await sql`update agent_memory_settings set enabled=${input.enabled},revision=revision+1 where athlete_id=${athleteId} returning enabled,revision::text`;
          if (!input.enabled)
            await sql`delete from athlete_memories where athlete_id=${athleteId} and source='learned'`;
          await resetMemoryContext(sql, athleteId);
        }
        return { enabled: Boolean(s!.enabled), revision: String(s!.revision) };
      }),
    memoriesV2: async (auth: string) =>
      withAthlete(client, auth, async (sql, a) => ({
        memories: (
          await sql<
            Row[]
          >`select * from athlete_memories where athlete_id=${String(a.id)} order by id`
        ).map((r) => LearnedMemory.parse(wire(r))),
      })),
  };
}
export async function validateV2Request(
  sql: Tx,
  athlete: Row,
  input: AnyInput,
) {
  if (input.schemaVersion !== 2) return;
  if (input.mutation) await assertScope(sql, athlete, input);
  if (input.native)
    await manifestFor(sql, String(athlete.id), input.native.deviceId);
}
