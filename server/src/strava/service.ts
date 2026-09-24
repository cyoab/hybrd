import { randomBytes, timingSafeEqual } from "node:crypto";
import type postgres from "postgres";
import type { z } from "zod";
import { ApiError } from "../api/errors";
import type { Env } from "../config/env";
import { type Row, type Tx, withAthlete } from "../db/store";
import { digest, seal } from "./crypto";
import { newHistory } from "./history";
import { onboardingPreview } from "./preview";
import { StravaError, type StravaProvider } from "./provider";
import { reserveRequest } from "./queue";
import { StatusSchema, type WebhookInput } from "./schemas";

export async function queueHistory(sql: Tx, connection: Row) {
  const athlete = String(connection.athlete_id),
    generation = String(connection.generation);
  const [pending] =
    await sql`select id from strava_jobs where athlete_id=${athlete} and generation=${generation} and kind='history' and state in ('queued','running','retry') limit 1`;
  if (pending) return String(pending.id);
  const state = newHistory();
  const preview = onboardingPreview(state, connection.scopes as string[]);
  await sql`update strava_connections set onboarding_preview=${sql.json(preview)},history=null,history_expires_at=${new Date(preview.expiresAt)} where athlete_id=${athlete}`;
  const [row] =
    await sql`insert into strava_jobs (athlete_id,generation,kind,payload) values (${athlete},${generation},'history',${sql.json(state)}) returning id`;
  return String(row?.id);
}
export function stravaServices(
  client: postgres.Sql,
  env: Env,
  provider: StravaProvider,
) {
  const requireAvailable = () => {
    if (!provider.available)
      throw new ApiError(
        503,
        "STRAVA_UNAVAILABLE",
        "Strava is not configured.",
      );
  };
  async function complete(
    state: string,
    code: string,
    scope: string,
    userId?: string,
  ) {
    requireAvailable();
    const states =
      await client`delete from strava_oauth_states s using athletes a where s.digest=${digest(state)} and s.athlete_id=a.id and s.expires_at>now() and (${userId ?? null}::text is null or a.auth_user_id=${userId ?? null}) returning s.*,a.auth_user_id`;
    const pending = states[0];
    if (!pending)
      throw new ApiError(
        400,
        "STRAVA_STATE_INVALID",
        "The connection request expired or was already used. Start again.",
      );
    const token = await (async () => {
      try {
        await reserveRequest(client);
        return await provider.exchange(code);
      } catch (error) {
        throw new ApiError(
          503,
          error instanceof StravaError ? error.code : "STRAVA_REQUEST_FAILED",
          "Strava connection could not be completed. Start again shortly.",
        );
      }
    })();
    if (!token.athlete)
      throw new ApiError(
        502,
        "STRAVA_INVALID_RESPONSE",
        "Strava did not identify the connected athlete.",
      );
    const remote = token.athlete.id,
      scopes = scope
        .split(/[ ,]+/)
        .filter((s) =>
          [
            "read",
            "activity:read",
            "activity:read_all",
            "activity:write",
            "profile:read_all",
          ].includes(s),
        );
    return withAthlete(
      client,
      String(pending.auth_user_id),
      async (sql, athlete) => {
        const athleteId = String(athlete.id);
        await sql`select pg_advisory_xact_lock(hashtextextended(${remote},22))`;
        const [current] =
          await sql`select * from strava_connections where athlete_id=${athleteId} for update`;
        if (
          current?.status === "disconnecting" ||
          (current?.tokens && current.remote_id !== remote)
        )
          throw new ApiError(
            409,
            "STRAVA_DISCONNECT_REQUIRED",
            "Finish disconnecting the previous Strava account first.",
          );
        await sql`delete from strava_connections where remote_id=${remote} and status='disconnected' and athlete_id<>${athleteId}`;
        const [owner] =
          await sql`select athlete_id from strava_connections where remote_id=${remote}`;
        if (owner && owner.athlete_id !== athleteId)
          throw new ApiError(
            409,
            "STRAVA_ALREADY_CONNECTED",
            "This Strava account is connected to another hybrd account.",
          );
        await sql`update strava_jobs set state='cancelled',payload=null,updated_at=now() where athlete_id=${athleteId} and state not in ('published','completed','cancelled')`;
        const generation = crypto.randomUUID();
        const [connection] = await sql<
          Row[]
        >`insert into strava_connections (athlete_id,remote_id,generation,tokens,scopes,expires_at,status,auto_publish)
        values (${athleteId},${remote},${generation},${seal(env.BETTER_AUTH_SECRET, athleteId, token)},${sql.json(scopes)},${new Date(token.expires_at * 1000)},'connected',${Boolean(pending.auto_publish) && scopes.includes("activity:write")})
        on conflict(athlete_id) do update set remote_id=excluded.remote_id,generation=excluded.generation,tokens=excluded.tokens,scopes=excluded.scopes,expires_at=excluded.expires_at,status='connected',auto_publish=excluded.auto_publish,connected_at=now(),history=null,onboarding_preview=null,history_expires_at=null returning *`;
        if (connection) await queueHistory(sql, connection);
        return { connected: true as const };
      },
    );
  }
  return {
    complete,
    status: (userId: string) =>
      withAthlete(client, userId, async (sql, athlete) => {
        const id = String(athlete.id),
          [c] =
            await sql`select * from strava_connections where athlete_id=${id}`;
        const jobs =
          await sql`select id,kind,workout_id,state,remote_id,error_code,updated_at from strava_jobs where athlete_id=${id} order by updated_at desc,id desc limit 30`;
        return StatusSchema.parse({
          available: provider.available,
          status: c?.status ?? "not_connected",
          remoteAthleteId: c?.remote_id ?? null,
          autoPublish: c?.auto_publish ?? false,
          scopes: c?.scopes ?? [],
          history:
            c?.history_expires_at && new Date(c.history_expires_at) > new Date()
              ? c.history
              : null,
          onboardingPreview:
            c?.history_expires_at && new Date(c.history_expires_at) > new Date()
              ? c.onboarding_preview
              : null,
          jobs: jobs.map((j) => ({
            id: j.id,
            kind: j.kind,
            workoutId: j.workout_id,
            state: j.state,
            remoteId: j.remote_id,
            errorCode: j.error_code,
            updatedAt: j.updated_at.toISOString(),
          })),
        });
      }),
    connect: (userId: string, autoPublish: boolean) =>
      withAthlete(client, userId, async (sql, athlete) => {
        requireAvailable();
        const state = randomBytes(32).toString("base64url"),
          id = String(athlete.id);
        const [current] =
          await sql`select status from strava_connections where athlete_id=${id}`;
        if (current?.status === "disconnecting")
          throw new ApiError(
            409,
            "STRAVA_DISCONNECT_PENDING",
            "Wait for Strava disconnection to finish.",
          );
        await sql`delete from strava_oauth_states where athlete_id=${id} or expires_at<=now()`;
        await sql`insert into strava_oauth_states (digest,athlete_id,auto_publish,expires_at) values (${digest(state)},${id},${autoPublish},now()+interval '10 minutes')`;
        const url = new URL("https://www.strava.com/oauth/mobile/authorize");
        url.search = new URLSearchParams({
          client_id: env.STRAVA_CLIENT_ID ?? "",
          redirect_uri: new URL(
            "/integrations/strava/callback",
            env.BETTER_AUTH_URL,
          ).href,
          response_type: "code",
          approval_prompt: "force",
          scope: `read,profile:read_all,activity:read_all${autoPublish ? ",activity:write" : ""}`,
          state,
        }).toString();
        return { authorizationUrl: url.href, state, expiresInSeconds: 600 };
      }),
    refreshHistory: (userId: string) =>
      withAthlete(client, userId, async (sql, athlete) => {
        requireAvailable();
        const [c] = await sql<
          Row[]
        >`select * from strava_connections where athlete_id=${String(athlete.id)} and status='connected'`;
        if (!c)
          throw new ApiError(
            409,
            "STRAVA_NOT_CONNECTED",
            "Connect Strava first.",
          );
        return { jobId: await queueHistory(sql, c) };
      }),
    settings: (userId: string, enabled: boolean) =>
      withAthlete(client, userId, async (sql, athlete) => {
        const id = String(athlete.id),
          [c] =
            await sql`select * from strava_connections where athlete_id=${id} and status='connected'`;
        if (!c)
          throw new ApiError(
            409,
            "STRAVA_NOT_CONNECTED",
            "Connect Strava first.",
          );
        if (enabled && !(c.scopes as string[]).includes("activity:write"))
          throw new ApiError(
            409,
            "STRAVA_SCOPE_REQUIRED",
            "Reconnect Strava with permission to publish workouts.",
          );
        await sql`update strava_connections set auto_publish=${enabled} where athlete_id=${id}`;
        if (!enabled)
          await sql`update strava_jobs set state='cancelled',payload=null,updated_at=now() where athlete_id=${id} and kind='publish' and state in ('queued','retry','running','needs_details') and payload is null`;
      }),
    disconnect: (userId: string) =>
      withAthlete(client, userId, async (sql, athlete) => {
        const id = String(athlete.id),
          [c] =
            await sql`select * from strava_connections where athlete_id=${id} for update`;
        await sql`delete from strava_oauth_states where athlete_id=${id}`;
        if (c?.status === "disconnecting") return;
        await sql`update strava_jobs set state='cancelled',payload=null,updated_at=now() where athlete_id=${id} and state not in ('published','completed','cancelled')`;
        if (!c || c.status === "disconnected") return;
        await sql`update strava_connections set auto_publish=false,history=null,onboarding_preview=null,history_expires_at=null,status='disconnecting' where athlete_id=${id}`;
        await sql`insert into strava_jobs (athlete_id,generation,kind) values (${id},${String(c.generation)},'revoke')`;
      }),
    retry: (userId: string, jobId: string) =>
      withAthlete(client, userId, async (sql, athlete) => {
        const rows =
          await sql`update strava_jobs j set state='queued',available_at=now(),attempts=0,error_code=null,updated_at=now()
        from strava_connections c where j.id=${jobId} and j.athlete_id=${String(athlete.id)} and c.athlete_id=j.athlete_id and c.generation=j.generation and c.status='connected'
        and j.state in ('failed','retry','needs_details') and (j.kind<>'publish' or c.auto_publish) returning j.id`;
        if (!rows.length)
          throw new ApiError(
            409,
            "STRAVA_JOB_NOT_RETRYABLE",
            "This job cannot be retried. An uncertain publish needs reconciliation to avoid duplicates.",
          );
      }),
    reconcile: (userId: string, jobId: string, remoteActivityId: string) =>
      withAthlete(client, userId, async (sql, athlete) => {
        const changed =
          await sql`update strava_jobs j set state='queued',payload=${sql.json({ reconcileActivityId: remoteActivityId })},attempts=0,available_at=now(),updated_at=now()
          from strava_connections c where j.id=${jobId} and j.athlete_id=${String(athlete.id)} and j.kind='publish' and j.state='needs_review'
          and c.athlete_id=j.athlete_id and c.generation=j.generation and c.status='connected' returning j.id`;
        if (!changed.length)
          throw new ApiError(
            409,
            "STRAVA_JOB_NOT_RECONCILABLE",
            "Only your uncertain publishes on the current connection can be reconciled.",
          );
      }),
    callback: async (input: {
      state?: string;
      code?: string;
      scope?: string;
      error?: string;
    }) => {
      let result = "failed";
      if (input.error) {
        if (input.state)
          await client`delete from strava_oauth_states where digest=${digest(input.state)}`;
        result = "cancelled";
      } else if (input.state && input.code) {
        try {
          await complete(input.state, input.code, input.scope ?? "");
          result = "connected";
        } catch {
          /* Never put tokens or provider messages in the return URL. */
        }
      }
      const url = new URL(env.STRAVA_APP_RETURN_URL);
      url.searchParams.set("status", result);
      return url.href;
    },
    verifyWebhook: (secret: string, token: string) => {
      if (
        !env.STRAVA_WEBHOOK_SECRET ||
        !env.STRAVA_WEBHOOK_VERIFY_TOKEN ||
        !timingSafeEqual(
          Buffer.from(digest(secret)),
          Buffer.from(digest(env.STRAVA_WEBHOOK_SECRET)),
        ) ||
        !timingSafeEqual(
          Buffer.from(digest(token)),
          Buffer.from(digest(env.STRAVA_WEBHOOK_VERIFY_TOKEN)),
        )
      )
        throw new ApiError(404, "NOT_FOUND", "Webhook unavailable.");
    },
    webhook: async (secret: string, event: z.infer<typeof WebhookInput>) => {
      if (
        !env.STRAVA_WEBHOOK_SECRET ||
        !timingSafeEqual(
          Buffer.from(digest(secret)),
          Buffer.from(digest(env.STRAVA_WEBHOOK_SECRET)),
        ) ||
        event.subscription_id !== env.STRAVA_WEBHOOK_SUBSCRIPTION_ID
      )
        throw new ApiError(404, "NOT_FOUND", "Webhook unavailable.");
      await client.begin(async (sql) => {
        const [c] = await sql<
          Row[]
        >`select * from strava_connections where remote_id=${event.owner_id} and status='connected' for update`;
        if (!c) return;
        const id = String(c.athlete_id);
        if (
          event.event_time <
          Math.floor(new Date(String(c.connected_at)).getTime() / 1000)
        )
          return;
        const fingerprint = digest(
          JSON.stringify([
            event.owner_id,
            event.object_type,
            event.object_id,
            event.aspect_type,
            event.event_time,
            Object.entries(event.updates).sort(([a], [b]) =>
              a.localeCompare(b),
            ),
          ]),
        );
        const inserted =
          await sql`insert into strava_webhook_receipts (digest,athlete_id) values (${fingerprint},${id}) on conflict do nothing returning digest`;
        if (!inserted.length) return;
        if (
          event.object_type === "athlete" &&
          String(event.updates.authorized) === "false"
        ) {
          await sql`update strava_connections set tokens=null,status='disconnected',auto_publish=false,history=null,onboarding_preview=null,history_expires_at=null where athlete_id=${id}`;
          await sql`update strava_jobs set state='cancelled',payload=null,updated_at=now() where athlete_id=${id} and state not in ('published','completed')`;
        } else if (event.object_type === "activity") {
          // Invalidate all derived previews immediately, including a pending import.
          await sql`update strava_connections set history=null,onboarding_preview=null,history_expires_at=null where athlete_id=${id}`;
          await sql`update strava_jobs set state='cancelled',payload=null,updated_at=now() where athlete_id=${id} and kind='history' and state in ('queued','retry','running')`;
          if (
            (c.scopes as string[]).some((s) =>
              ["activity:read", "activity:read_all"].includes(s),
            )
          )
            await queueHistory(sql, c);
        }
      });
    },
  };
}
