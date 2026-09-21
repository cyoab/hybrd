import type postgres from "postgres";
import { ApiError } from "../api/errors";
import { hash, withAthlete } from "../db/store";
import type { PushKind, PushProvider, PushResult } from "./provider";
export function notificationServices(
  client: postgres.Sql,
  provider: PushProvider,
) {
  return {
    send: async (
      authUserId: string,
      deviceId: string,
      id: string,
      kind: PushKind,
    ) => {
      const fingerprint = hash({ deviceId, kind });
      const reservation = await withAthlete(
        client,
        authUserId,
        async (sql, athlete) => {
          const [prior] =
            await sql`select * from push_deliveries where id=${id}`;
          if (prior) {
            if (
              prior.athlete_id !== athlete.id ||
              prior.request_hash !== fingerprint
            )
              throw new ApiError(
                409,
                "IDEMPOTENCY_KEY_REUSED",
                "Use a new delivery ID.",
              );
            if (prior.status === "pending")
              throw new ApiError(
                409,
                "PUSH_INDETERMINATE",
                "This delivery is pending or has an uncertain outcome; it will not be sent twice.",
              );
            return { cached: { status: prior.status, reason: prior.reason } };
          }
          if (!provider.available)
            throw new ApiError(
              503,
              "PUSH_NOT_CONFIGURED",
              "APNs is not configured.",
            );
          const [device] =
            await sql`select * from device_installations where id=${deviceId} and athlete_id=${String(athlete.id)} and revoked_at is null and push_enabled=true and push_token is not null`;
          if (!device)
            throw new ApiError(
              409,
              "PUSH_DISABLED",
              "This installation has not enabled push notifications.",
            );
          await sql`insert into push_deliveries (id,athlete_id,device_id,request_hash,status) values (${id},${String(athlete.id)},${deviceId},${fingerprint},'pending')`;
          return { device, athleteId: String(athlete.id) };
        },
      );
      if (reservation.cached) return reservation.cached;
      let outcome: PushResult;
      try {
        outcome = await provider.send({
          id,
          token: reservation.device.push_token,
          environment: reservation.device.push_environment,
          kind,
        });
      } catch {
        outcome = { status: 0, reason: "TransportError" };
      }
      const status =
        outcome.status === 200
          ? "sent"
          : outcome.status === 0
            ? "unknown"
            : "failed";
      await client.begin(async (sql) => {
        // Do not recreate audit data when the account was deleted during delivery.
        await sql`update push_deliveries set status=${status},reason=${outcome.reason ?? null} where id=${id}`;
        if (
          outcome.status === 410 ||
          ["BadDeviceToken", "DeviceTokenNotForTopic"].includes(
            outcome.reason ?? "",
          )
        )
          await sql`update device_installations set push_enabled=false,push_token=null where id=${deviceId} and athlete_id=${reservation.athleteId} and push_token=${reservation.device.push_token} and push_environment=${reservation.device.push_environment}`;
      });
      return { status, reason: outcome.reason ?? null };
    },
  };
}
