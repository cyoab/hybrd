import { and, desc, eq, isNull, sql } from "drizzle-orm";
import { requireAthlete } from "../athlete/repository";
import type { createAuth } from "../auth";
import type { createDatabase } from "../db/client";
import {
  deviceInstallations,
  entitlements,
  syncChangeLog,
  trainingPolicyVersions,
} from "../db/schema";
import type { AppDependencies } from "./dependencies";
import { ApiError } from "./errors";
import {
  AthleteSchema,
  EntitlementSchema,
  TrainingPolicySchema,
} from "./schemas";

export function createServices(
  database: ReturnType<typeof createDatabase>,
  auth: ReturnType<typeof createAuth>,
): AppDependencies {
  const { db } = database;

  async function trainingPolicy() {
    const [policy] = await db
      .select()
      .from(trainingPolicyVersions)
      .where(eq(trainingPolicyVersions.status, "published"))
      .orderBy(desc(trainingPolicyVersions.version))
      .limit(1);
    return policy ? TrainingPolicySchema.parse(policy) : null;
  }

  async function athleteEntitlements(athleteId: string) {
    const rows = await db
      .select()
      .from(entitlements)
      .where(eq(entitlements.athleteId, athleteId));
    return rows.map((row) =>
      EntitlementSchema.parse({
        key: row.entitlementKey,
        status: row.status,
        validUntil: row.validUntil?.toISOString() ?? null,
      }),
    );
  }

  return {
    checkDatabase: async () => {
      await database.client`select 1`;
    },
    authenticate: async (headers) =>
      (await auth.api.getSession({ headers }))?.user.id ?? null,
    handleAuth: async (request) => auth.handler(request),
    trainingPolicy,
    bootstrap: async (authUserId, deviceId) => {
      const athlete = await requireAthlete(db, authUserId);
      const [policy, access, sequence, devices] = await Promise.all([
        trainingPolicy(),
        athleteEntitlements(athlete.id),
        db
          .select({
            latest: sql<string>`coalesce(max(${syncChangeLog.sequence}), 0)::text`,
          })
          .from(syncChangeLog)
          .where(eq(syncChangeLog.athleteId, athlete.id)),
        deviceId
          ? db
              .select({ id: deviceInstallations.id })
              .from(deviceInstallations)
              .where(
                and(
                  eq(deviceInstallations.id, deviceId),
                  eq(deviceInstallations.athleteId, athlete.id),
                  isNull(deviceInstallations.revokedAt),
                ),
              )
              .limit(1)
          : Promise.resolve([]),
      ]);
      return {
        athlete: AthleteSchema.parse({
          ...athlete,
          revision: athlete.revision.toString(),
        }),
        device: { registered: devices.length > 0 },
        sync: { available: false, latestSequence: sequence[0]?.latest ?? "0" },
        policy: policy
          ? { version: policy.version, checksum: policy.checksum }
          : null,
        entitlements: access,
      };
    },
    registerDevice: async (authUserId, deviceId, input) => {
      const athlete = await requireAthlete(db, authUserId);
      const values = {
        ...input,
        pushToken: input.pushToken ?? null,
        osVersion: input.osVersion ?? null,
        lastSeenAt: new Date(),
        revokedAt: null,
      };
      const rows = await db
        .insert(deviceInstallations)
        .values({ id: deviceId, athleteId: athlete.id, ...values })
        .onConflictDoUpdate({
          target: deviceInstallations.id,
          set: values,
          setWhere: eq(deviceInstallations.athleteId, athlete.id),
        })
        .returning({ id: deviceInstallations.id });
      if (!rows.length)
        throw new ApiError(
          409,
          "DEVICE_ID_UNAVAILABLE",
          "Use a new installation ID.",
        );
    },
    revokeDevice: async (authUserId, deviceId) => {
      const athlete = await requireAthlete(db, authUserId);
      await db
        .update(deviceInstallations)
        .set({ revokedAt: new Date(), pushEnabled: false, pushToken: null })
        .where(
          and(
            eq(deviceInstallations.id, deviceId),
            eq(deviceInstallations.athleteId, athlete.id),
            isNull(deviceInstallations.revokedAt),
          ),
        );
    },
    entitlements: async (authUserId) =>
      athleteEntitlements((await requireAthlete(db, authUserId)).id),
  };
}
