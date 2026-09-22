import type { createAuth } from "../auth";
import { effectiveEntitlements } from "../billing/entitlements";
import { billingServices } from "../billing/service";
import { type AppleVerifier, appleVerifier } from "../billing/verifier";
import { readCatalog } from "../catalog/service";
import { type Env, readEnv } from "../config/env";
import type { createDatabase } from "../db/client";
import { ensureInitialChange, wire, withAthlete } from "../db/store";
import {
  type IntelligenceProvider,
  openRouterProvider,
} from "../intelligence/provider";
import { intelligenceServices } from "../intelligence/service";
import { type ProgressOptions, progressServices } from "../progress/service";
import { exportTraining, syncServices } from "../sync/service";
import type { AppDependencies } from "./dependencies";
import { ApiError } from "./errors";
import { AthleteSchema, TrainingPolicySchema } from "./schemas";

export function createServices(
  database: ReturnType<typeof createDatabase>,
  auth: ReturnType<typeof createAuth>,
  options: {
    env?: Env;
    intelligence?: IntelligenceProvider;
    apple?: AppleVerifier;
    progress?: ProgressOptions;
  } = {},
): AppDependencies {
  const { client } = database;
  const env = options.env ?? readEnv();
  const intelligence = options.intelligence ?? openRouterProvider(env),
    apple = options.apple ?? appleVerifier(env);
  async function trainingPolicy() {
    const [policy] =
      await client`select * from training_policy_versions where status='published' order by version desc limit 1`;
    return policy ? TrainingPolicySchema.parse(wire(policy)) : null;
  }
  return {
    progress: progressServices(
      client,
      env.BETTER_AUTH_SECRET,
      options.progress,
    ),
    billing: billingServices(client, env, apple),
    sync: syncServices(client),
    intelligence: intelligenceServices(client, env, intelligence),
    catalog: () => readCatalog(client),
    exportAccount: (authUserId) =>
      withAthlete(client, authUserId, exportTraining),
    deleteAccount: async (authUserId, headers) => {
      const session = await auth.api.getSession({ headers });
      if (
        !session ||
        session.user.id !== authUserId ||
        Date.now() - new Date(session.session.createdAt).getTime() > 600_000
      )
        throw new ApiError(
          403,
          "REAUTHENTICATION_REQUIRED",
          "Sign in again before deleting your account.",
        );
      await withAthlete(client, authUserId, async (sql) => {
        await sql`delete from auth_user where id=${authUserId}`;
      });
    },
    checkDatabase: async () => {
      await client`select 1`;
    },
    authenticate: async (headers) =>
      (await auth.api.getSession({ headers }))?.user.id ?? null,
    handleAuth: (request) => auth.handler(request),
    trainingPolicy,
    bootstrap: async (authUserId, deviceId) =>
      withAthlete(client, authUserId, async (sql, athlete) => {
        await ensureInitialChange(sql, athlete);
        const athleteId = String(athlete.id),
          access = await effectiveEntitlements(sql, athleteId);
        const [policy, sequence, devices] = await Promise.all([
          trainingPolicy(),
          sql`select coalesce(max(sequence),0)::text as value from sync_change_log where athlete_id=${athleteId}`,
          deviceId
            ? sql`select id from device_installations where id=${deviceId} and athlete_id=${athleteId} and revoked_at is null`
            : Promise.resolve([]),
        ]);
        return {
          athlete: AthleteSchema.parse(wire(athlete)),
          device: { registered: devices.length > 0 },
          capabilities: {
            remoteDecisions:
              intelligence.available("decision") &&
              Boolean(
                (policy?.config.features as Record<string, unknown> | undefined)
                  ?.remoteDecisions,
              ),
            remoteCoach:
              intelligence.available("chat") &&
              Boolean(
                (policy?.config.features as Record<string, unknown> | undefined)
                  ?.remoteCoach,
              ),
            billing: apple.available,
            push: Boolean(env.APNS_KEY_ID && env.APNS_TOPIC),
          },
          sync: {
            available: true,
            latestSequence: String(sequence[0]?.value ?? "0"),
          },
          policy: policy
            ? { version: policy.version, checksum: policy.checksum }
            : null,
          entitlements: access,
        };
      }),
    registerDevice: async (authUserId, deviceId, input) =>
      withAthlete(client, authUserId, async (sql, athlete) => {
        const rows =
          await sql`insert into device_installations (id,athlete_id,app_version,os_version,push_token,push_enabled,push_environment) values (${deviceId},${String(athlete.id)},${input.appVersion},${input.osVersion ?? null},${input.pushToken ?? null},${input.pushEnabled},${input.pushEnvironment}) on conflict(id) do update set app_version=excluded.app_version,os_version=excluded.os_version,push_token=excluded.push_token,push_enabled=excluded.push_enabled,push_environment=excluded.push_environment,last_seen_at=now(),revoked_at=null where device_installations.athlete_id=excluded.athlete_id returning id`;
        if (!rows.length)
          throw new ApiError(
            409,
            "DEVICE_ID_UNAVAILABLE",
            "Use a new installation ID.",
          );
      }),
    revokeDevice: async (authUserId, deviceId) =>
      withAthlete(client, authUserId, async (sql, athlete) => {
        await sql`update device_installations set revoked_at=now(),push_enabled=false,push_token=null where id=${deviceId} and athlete_id=${String(athlete.id)} and revoked_at is null`;
      }),
    entitlements: (authUserId) =>
      withAthlete(client, authUserId, async (sql, athlete) => {
        await ensureInitialChange(sql, athlete);
        return effectiveEntitlements(sql, String(athlete.id));
      }),
  };
}
