import type postgres from "postgres";
import type { Env } from "../config/env";
import type { Row } from "../db/store";
import { log } from "../telemetry/logger";
import { seal, unseal } from "./crypto";
import {
  bestCandidates,
  type HistoryState,
  historyPreview,
  newHistory,
  summarizeActivity,
} from "./history";
import { onboardingPreview } from "./preview";
import {
  type PublishActivity,
  StravaError,
  type StravaProvider,
} from "./provider";
import { reserveRequest } from "./queue";

function localDate(instant: Date, timezone: string) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(instant);
  const value = (type: string) => parts.find((p) => p.type === type)?.value;
  // Strava's start_date_local is wall-clock time, not an actual UTC instant.
  return `${value("year")}-${value("month")}-${value("day")}T${value("hour")}:${value("minute")}:${value("second")}Z`;
}
export function publishPayload(workout: Row): PublishActivity | null {
  const duration = Number(workout.duration_s ?? workout.run_duration_s ?? 0);
  if (!workout.started_at || duration <= 0 || !Number.isFinite(duration))
    return null;
  return {
    name:
      workout.discipline === "running" ? "hybrd run" : "hybrd strength workout",
    sport_type: workout.discipline === "running" ? "Run" : "WeightTraining",
    start_date_local: localDate(
      new Date(String(workout.started_at)),
      String(workout.timezone),
    ),
    elapsed_time: Math.round(duration),
    ...(workout.discipline === "running"
      ? { distance: Number(workout.distance_m ?? 0) }
      : {}),
    description: `Recorded with hybrd. Reference: hybrd:${String(workout.id)}`,
  };
}

export async function processStravaJob(
  client: postgres.Sql,
  env: Env,
  provider: StravaProvider,
) {
  const lock = await client.reserve();
  let locked = false;
  try {
    const [got] = await lock`select pg_try_advisory_lock(473920,1) as acquired`;
    locked = Boolean(got?.acquired);
    if (!locked) return false;
    // Retention runs even when provider credentials are temporarily disabled.
    await client`update strava_connections set history=null,onboarding_preview=null,history_expires_at=null where history_expires_at<=now()`;
    await client`update strava_jobs set payload=null where kind='history' and (payload->>'before')::bigint < extract(epoch from now()-interval '7 days')`;
    if (!provider.available) return false;
    // The session lock proves no other worker is active. A prior publishing
    // process may have died after Strava accepted it: never blindly POST again.
    await client`update strava_jobs set state=case when state='publishing' then 'needs_review' else 'retry' end,error_code=case when state='publishing' then 'STRAVA_DELIVERY_UNKNOWN' else 'WORKER_RESTARTED' end,available_at=now(),updated_at=now() where state in ('running','publishing')`;
    await client`delete from strava_oauth_states where expires_at<=now()`;
    await client`delete from strava_webhook_receipts where received_at<now()-interval '7 days'`;
    await client`delete from strava_revocations where created_at<now()-interval '7 days'`;
    const [revocation] =
      await client`select * from strava_revocations where available_at<=now() order by available_at limit 1`;
    if (revocation) {
      try {
        await reserveRequest(client);
        const tokens = unseal(
          env.BETTER_AUTH_SECRET,
          String(revocation.owner),
          String(revocation.tokens),
        );
        await provider.revoke(tokens.refresh_token);
        await client`delete from strava_revocations where owner=${revocation.owner}`;
      } catch {
        await client`update strava_revocations set attempts=attempts+1,available_at=now()+least(86400,60*power(2,least(attempts,10)))*interval '1 second' where owner=${revocation.owner}`;
        log({
          event: "strava_revocation_retry",
          errorType: "StravaRevocationError",
        });
      }
      return true;
    }
    const [job] = await client<
      Row[]
    >`update strava_jobs set state='running',attempts=attempts+1,updated_at=now()
      where id=(select id from strava_jobs where state in ('queued','retry') and available_at<=now() order by case kind when 'revoke' then 0 when 'publish' then 1 else 2 end,available_at,id limit 1)
      returning *`;
    if (!job) return false;
    const id = String(job.id),
      owner = String(job.athlete_id),
      generation = String(job.generation);
    const [connection] = await client<
      Row[]
    >`select * from strava_connections where athlete_id=${owner} and generation=${generation}`;
    const finish = async (state: string, error: string | null = null) => {
      await client`update strava_jobs set state=${state},error_code=${error},payload=null,updated_at=now() where id=${id} and state in ('running','publishing')`;
    };
    if (
      !connection?.tokens ||
      (job.kind !== "revoke" && connection.status !== "connected")
    ) {
      await finish("cancelled");
      return true;
    }
    let publicationStarted = false;
    const reconcileId =
      job.kind === "publish"
        ? (job.payload as { reconcileActivityId?: string } | null)
            ?.reconcileActivityId
        : undefined;
    try {
      let tokens = unseal(
        env.BETTER_AUTH_SECRET,
        owner,
        String(connection.tokens),
      );
      if (job.kind === "revoke") {
        await reserveRequest(client);
        await provider.revoke(tokens.refresh_token);
        await client`update strava_connections set tokens=null,status='disconnected',auto_publish=false,history=null,onboarding_preview=null,history_expires_at=null where athlete_id=${owner} and generation=${generation}`;
        await finish("completed");
        return true;
      }
      if (
        new Date(String(connection.expires_at)).getTime() <=
        Date.now() + 60_000
      ) {
        await reserveRequest(client);
        const refreshed = await provider.refresh(tokens.refresh_token);
        const updated =
          await client`update strava_connections set tokens=${seal(env.BETTER_AUTH_SECRET, owner, refreshed)},expires_at=${new Date(refreshed.expires_at * 1000)} where athlete_id=${owner} and generation=${generation} and status in ('connected','disconnecting') returning athlete_id`;
        if (!updated.length) {
          // Deletion may have queued the pre-rotation token while refresh was in
          // flight. Retain only the newest revocation envelope, never user data.
          await client`insert into strava_revocations (owner,tokens)
            select ${owner}::uuid,${seal(env.BETTER_AUTH_SECRET, owner, refreshed)} where not exists(select 1 from athletes where id=${owner})
            on conflict(owner) do update set tokens=excluded.tokens,available_at=now()`;
          await finish("cancelled");
          return true;
        }
        tokens = refreshed;
      }
      // Check generation and cancellation again after potentially slow refresh.
      const [active] =
        await client`select j.id from strava_jobs j join strava_connections c on c.athlete_id=j.athlete_id where j.id=${id} and j.state='running' and c.generation=${generation} and c.status='connected'`;
      if (!active) return true;
      if (job.kind === "publish") {
        if (reconcileId) {
          await reserveRequest(client);
          const remote = await provider.detail(
            tokens.access_token,
            reconcileId,
          );
          if (
            remote.id !== reconcileId ||
            remote.description !==
              `Recorded with hybrd. Reference: hybrd:${String(job.workout_id)}`
          ) {
            await finish("needs_review", "STRAVA_ACTIVITY_MISMATCH");
            return true;
          }
          await client`update strava_jobs set state='published',remote_id=${remote.id},error_code=null,payload=null,updated_at=now() where id=${id} and state='running'`;
          return true;
        }
        const [w] = await client<
          Row[]
        >`select w.*,r.distance_m,r.duration_s as run_duration_s from workout_results w left join run_results r on r.workout_result_id=w.id where w.id=${String(job.workout_id)} and w.athlete_id=${owner} and w.deleted_at is null`;
        if (
          !connection.auto_publish ||
          !w ||
          w.source_type !== "manual" ||
          !["completed", "partial", "modified"].includes(
            String(w.completion_status),
          )
        ) {
          await finish("cancelled");
          return true;
        }
        const payload = publishPayload(w);
        if (!payload) {
          await finish("needs_details", "WORKOUT_EXPORT_INCOMPLETE");
          return true;
        }
        await reserveRequest(client);
        const changed =
          await client`update strava_jobs set state='publishing',updated_at=now() where id=${id} and state='running' returning id`;
        if (!changed.length) return true;
        publicationStarted = true;
        const remoteId = await provider.publish(tokens.access_token, payload);
        await client`update strava_jobs set state='published',remote_id=${remoteId},error_code=null,payload=null,updated_at=now() where id=${id} and state='publishing'`;
      } else {
        const history = job.payload as HistoryState | null;
        if (!history) {
          await finish("failed", "HISTORY_EXPIRED");
          return true;
        }
        // In-flight jobs from an older deployment restart with the new preview identity.
        if (!history.previewId) Object.assign(history, newHistory());
        const scopes = connection.scopes as string[];
        if (history.phase === "profile") {
          if (scopes.some((s) => ["read", "profile:read_all"].includes(s))) {
            try {
              await reserveRequest(client);
              const profile = await provider.profile(tokens.access_token);
              history.profileFetchedAt = new Date().toISOString();
              history.profile = {
                preferredName: profile.firstname,
                weightKg: scopes.includes("profile:read_all")
                  ? profile.weight
                  : null,
              };
            } catch (error) {
              if (
                error instanceof StravaError &&
                [
                  "STRAVA_RATE_LIMITED",
                  "STRAVA_REAUTHENTICATION_REQUIRED",
                ].includes(error.code)
              )
                throw error;
              history.profileFailure =
                error instanceof StravaError
                  ? error.code
                  : "STRAVA_INVALID_RESPONSE";
            }
          }
          history.phase = "zones";
        } else if (history.phase === "zones") {
          if (scopes.includes("profile:read_all")) {
            try {
              await reserveRequest(client);
              const zones = (await provider.zones(tokens.access_token))
                .heart_rate;
              history.zonesFetchedAt = new Date().toISOString();
              history.zones = zones
                ? {
                    custom: zones.custom_zones,
                    ranges: zones.zones.map((z) => ({
                      minBpm: z.min,
                      maxBpm: z.max < 0 ? null : z.max,
                    })),
                  }
                : null;
              history.zonesUnavailable = !zones;
            } catch (error) {
              if (
                error instanceof StravaError &&
                [
                  "STRAVA_RATE_LIMITED",
                  "STRAVA_REAUTHENTICATION_REQUIRED",
                ].includes(error.code)
              )
                throw error;
              history.zonesUnavailable = true;
              history.zonesFailure =
                error instanceof StravaError
                  ? error.code
                  : "STRAVA_INVALID_RESPONSE";
            }
          } else history.zonesUnavailable = true;
          history.phase = scopes.some((s) =>
            ["activity:read", "activity:read_all"].includes(s),
          )
            ? "pages"
            : "bests";
        } else if (history.phase === "pages") {
          await reserveRequest(client);
          const activities = await provider.activities(
            tokens.access_token,
            history.after,
            history.before,
            history.page,
          );
          const rows = new Map(history.activities.map((a) => [a.id, a]));
          for (const activity of activities) {
            const time = Date.parse(activity.start_date) / 1000;
            if (
              time >= history.after &&
              time < history.before &&
              !activity.flagged
            )
              rows.set(activity.id, summarizeActivity(activity));
          }
          history.activities = [...rows.values()];
          history.page++;
          if (activities.length < 200 || history.page > 10) {
            history.complete = activities.length < 200;
            history.phase = "bests";
            history.candidates = bestCandidates(history.activities);
          }
        } else if (history.detailIndex < history.candidates.length) {
          const candidate = history.candidates[history.detailIndex];
          if (!candidate) throw new Error("Missing history candidate");
          try {
            await reserveRequest(client);
            const detail = await provider.detail(
              tokens.access_token,
              candidate,
            );
            if (!detail.flagged && !detail.manual)
              for (const effort of detail.best_efforts) {
                const old = history.bests.find(
                  (b) => b.distanceM === effort.distance,
                );
                if (!old || effort.elapsed_time < old.elapsedSeconds) {
                  history.bests = history.bests.filter(
                    (b) => b.distanceM !== effort.distance,
                  );
                  history.bests.push({
                    name: effort.name,
                    distanceM: effort.distance,
                    elapsedSeconds: effort.elapsed_time,
                    activityId: detail.id,
                    performedAt: effort.start_date ?? detail.start_date,
                  });
                }
              }
          } catch (error) {
            if (
              !(
                error instanceof StravaError &&
                ["STRAVA_NOT_FOUND", "STRAVA_SCOPE_REQUIRED"].includes(
                  error.code,
                )
              )
            )
              throw error;
          }
          history.detailIndex++;
        }
        const done =
          history.phase === "bests" &&
          history.detailIndex >= history.candidates.length;
        history.revision++;
        await client.begin(async (sql) => {
          // Match webhook lock ordering so a deletion cannot restore stale data.
          const [current] =
            await sql`select athlete_id from strava_connections where athlete_id=${owner} and generation=${generation} and status='connected' for update`;
          if (!current) return;
          const changed =
            await sql`update strava_jobs set state=${done ? "completed" : "queued"},payload=${done ? null : sql.json(history)},attempts=0,error_code=null,available_at=now()+interval '1 second',updated_at=now() where id=${id} and state='running' returning id`;
          if (!changed.length) return;
          const onboarding = onboardingPreview(history, scopes);
          await sql`update strava_connections set onboarding_preview=${sql.json(onboarding)},history_expires_at=${new Date(onboarding.expiresAt)} where athlete_id=${owner}`;
          // Volume/pace/zones are usable before optional PB detail requests finish.
          if (
            history.phase === "bests" &&
            scopes.some((s) =>
              ["activity:read", "activity:read_all"].includes(s),
            )
          ) {
            const preview = historyPreview(history);
            await sql`update strava_connections set history=${sql.json(preview)},history_expires_at=${new Date(preview.expiresAt)} where athlete_id=${owner} and generation=${generation} and status='connected'`;
          }
        });
      }
    } catch (error) {
      const failure =
        error instanceof StravaError
          ? error
          : new StravaError("STRAVA_REQUEST_FAILED", 60, publicationStarted);
      if (failure.code === "STRAVA_REAUTHENTICATION_REQUIRED")
        await client`update strava_connections set status='reauthentication_required',auto_publish=false,history=null,onboarding_preview=null,history_expires_at=null where athlete_id=${owner} and generation=${generation} and status='connected'`;
      if (failure.code === "STRAVA_RATE_LIMITED")
        await client`update strava_budget set blocked_until=greatest(coalesce(blocked_until,now()),now()+${failure.retryAfter}*interval '1 second') where id=1`;
      const retry =
        failure.retryAfter > 0 &&
        !failure.ambiguous &&
        (Number(job.attempts) < 8 || failure.code === "STRAVA_RATE_LIMITED");
      const state =
        failure.ambiguous || (reconcileId && !retry)
          ? "needs_review"
          : retry
            ? "retry"
            : "failed";
      const delay = Math.min(
        86400,
        Math.max(failure.retryAfter, 2 ** Number(job.attempts) * 5),
      );
      await client`update strava_jobs set state=${state},error_code=${failure.code},available_at=now()+${delay}*interval '1 second',updated_at=now() where id=${id} and state in ('running','publishing')`;
      if (job.kind === "history") {
        await client.begin(async (sql) => {
          const [c] =
            await sql`select onboarding_preview from strava_connections where athlete_id=${owner} and generation=${generation} and status='connected' for update`;
          const [j] = await sql`select state from strava_jobs where id=${id}`;
          if (
            !c?.onboarding_preview ||
            !["retry", "failed"].includes(String(j?.state))
          )
            return;
          const preview = c.onboarding_preview;
          for (const section of [
            preview.profile,
            preview.heartRateZones,
            preview.runningHistory,
          ])
            if (section.state === "pending") {
              section.state = retry ? "pending" : "failed";
              section.reason =
                failure.code === "STRAVA_RATE_LIMITED"
                  ? "rate_limited"
                  : "provider_unavailable";
              section.retryAfterSeconds = retry ? delay : null;
            }
          await sql`update strava_connections set onboarding_preview=${sql.json(preview)} where athlete_id=${owner}`;
        });
      }
    }
    return true;
  } finally {
    if (locked) await lock`select pg_advisory_unlock(473920,1)`;
    lock.release();
  }
}

export function startStravaWorker(
  client: postgres.Sql,
  env: Env,
  provider: StravaProvider,
) {
  let stopping = false;
  const loop = (async () => {
    while (!stopping) {
      try {
        await processStravaJob(client, env, provider);
      } catch {
        log({ event: "strava_worker_error", errorType: "StravaWorkerError" });
      }
      if (!stopping) await Bun.sleep(1000);
    }
  })();
  return async () => {
    stopping = true;
    await loop;
  };
}
