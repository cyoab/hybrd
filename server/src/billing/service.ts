import type {
  JWSRenewalInfoDecodedPayload,
  JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";
import type postgres from "postgres";
import { z } from "zod";
import { ApiError } from "../api/errors";
import type { Env } from "../config/env";
import {
  ensureInitialChange,
  lockAthlete,
  type Row,
  type Tx,
  withAthlete,
} from "../db/store";
import { effectiveEntitlements } from "./entitlements";
import type { AppleVerifier } from "./verifier";

const transactionSchema = z.object({
  transactionId: z.string().min(1).max(100),
  originalTransactionId: z.string().min(1).max(100),
  bundleId: z.string(),
  productId: z.string(),
  appAccountToken: z.string().uuid(),
  environment: z.enum(["Sandbox", "Production"]),
  purchaseDate: z.number().int().positive(),
  expiresDate: z.number().int().positive(),
  signedDate: z.number().int().positive(),
  revocationDate: z.number().int().positive().optional(),
  isUpgraded: z.boolean().optional(),
  type: z.literal("Auto-Renewable Subscription"),
});
type Transaction = z.infer<typeof transactionSchema>;
export function billingServices(
  client: postgres.Sql,
  env: Env,
  verifier: AppleVerifier,
) {
  const products = JSON.parse(env.STOREKIT_PRODUCTS) as Record<string, string>;
  function validate(raw: JWSTransactionDecodedPayload) {
    const parsed = transactionSchema.safeParse(raw);
    if (
      !parsed.success ||
      parsed.data.bundleId !== env.STOREKIT_BUNDLE_ID ||
      parsed.data.environment !== env.STOREKIT_ENVIRONMENT ||
      !Object.hasOwn(products, parsed.data.productId)
    )
      throw new ApiError(
        400,
        "INVALID_APPLE_TRANSACTION",
        "Expected a supported subscription for this app and environment with an appAccountToken.",
      );
    return parsed.data;
  }
  async function apply(
    sql: Tx,
    athlete: Row,
    txn: Transaction,
    notification?: {
      type: string;
      signedDate: number;
      renewal?: JWSRenewalInfoDecodedPayload;
    },
  ) {
    const athleteId = String(athlete.id);
    await ensureInitialChange(sql, athlete);
    if (txn.appAccountToken.toLowerCase() !== athleteId.toLowerCase())
      throw new ApiError(
        403,
        "PURCHASE_ACCOUNT_MISMATCH",
        "The purchase is associated with a different athlete.",
      );
    await sql`select pg_advisory_xact_lock(hashtextextended(${txn.originalTransactionId},2))`;
    const [chainOwner] =
      await sql`select athlete_id from storekit_transactions where original_transaction_id=${txn.originalTransactionId} limit 1`;
    const [existing] =
      await sql`select * from storekit_transactions where transaction_id=${txn.transactionId}`;
    if (
      (chainOwner && chainOwner.athlete_id !== athleteId) ||
      (existing && existing.athlete_id !== athleteId)
    )
      throw new ApiError(
        409,
        "PURCHASE_ALREADY_CLAIMED",
        "This purchase is already associated with another account.",
      );
    const renewal = notification?.renewal;
    if (
      renewal &&
      (renewal.originalTransactionId !== txn.originalTransactionId ||
        renewal.environment !== env.STOREKIT_ENVIRONMENT ||
        (renewal.appAccountToken &&
          renewal.appAccountToken.toLowerCase() !== athleteId.toLowerCase()))
    )
      throw new ApiError(
        400,
        "INVALID_RENEWAL",
        "Renewal information does not belong to this subscription.",
      );
    const signedAt = new Date(
      Math.max(
        txn.signedDate,
        notification?.signedDate ?? 0,
        renewal?.signedDate ?? 0,
      ),
    );
    if (!existing || signedAt > existing.signed_at) {
      let revoked = txn.revocationDate ? new Date(txn.revocationDate) : null;
      if (
        txn.isUpgraded ||
        notification?.type === "REVOKE" ||
        notification?.type === "REFUND"
      )
        revoked ??= signedAt;
      // A normal transaction submission cannot erase a later server-side revocation.
      if (
        existing?.revoked_at &&
        !revoked &&
        notification?.type !== "REFUND_REVERSED"
      )
        revoked = existing.revoked_at;
      const grace =
        renewal?.isInBillingRetryPeriod && renewal.gracePeriodExpiresDate
          ? new Date(renewal.gracePeriodExpiresDate)
          : notification
            ? null
            : (existing?.grace_until ?? null);
      const entitlementKey = products[txn.productId];
      if (!entitlementKey)
        throw new Error("Validated product mapping disappeared");
      await sql`insert into storekit_transactions (transaction_id,athlete_id,original_transaction_id,product_id,entitlement_key,environment,purchased_at,expires_at,grace_until,revoked_at,signed_at,verified_payload) values (${txn.transactionId},${athleteId},${txn.originalTransactionId},${txn.productId},${entitlementKey},${txn.environment},${new Date(txn.purchaseDate)},${new Date(txn.expiresDate)},${grace},${revoked},${signedAt},${sql.json({ type: txn.type, isUpgraded: txn.isUpgraded ?? false })}) on conflict(transaction_id) do update set expires_at=excluded.expires_at,grace_until=excluded.grace_until,revoked_at=excluded.revoked_at,signed_at=excluded.signed_at,verified_payload=excluded.verified_payload`;
    }

    return effectiveEntitlements(sql, athleteId);
  }
  return {
    submit: async (authUserId: string, signedTransaction: string) => {
      if (!verifier.available)
        throw new ApiError(
          503,
          "BILLING_NOT_CONFIGURED",
          "Apple verification is not configured.",
        );
      const txn = validate(await verifier.transaction(signedTransaction));
      return {
        entitlements: await withAthlete(client, authUserId, (sql, athlete) =>
          apply(sql, athlete, txn),
        ),
      };
    },
    notification: async (signedPayload: string) => {
      if (!verifier.available)
        throw new ApiError(
          503,
          "BILLING_NOT_CONFIGURED",
          "Apple verification is not configured.",
        );
      const payload = await verifier.notification(signedPayload),
        id = z.string().uuid().safeParse(payload.notificationUUID);
      if (!id.success || !payload.notificationType || !payload.signedDate)
        throw new ApiError(
          400,
          "INVALID_APPLE_NOTIFICATION",
          "Required notification fields are missing.",
        );
      const type = String(payload.notificationType),
        signedDate = payload.signedDate;
      if (type === "TEST") return;
      if (!payload.data?.signedTransactionInfo)
        throw new ApiError(
          400,
          "INVALID_APPLE_NOTIFICATION",
          "This notification has no subscription transaction.",
        );
      const txn = validate(
        await verifier.transaction(payload.data.signedTransactionInfo),
      );
      const renewal = payload.data.signedRenewalInfo
        ? await verifier.renewal(payload.data.signedRenewalInfo)
        : undefined;
      await client.begin(async (sql) => {
        // The athlete lock precedes the notification lock, matching all domain writers.
        const [exists] =
          await sql`select id from athletes where id=${txn.appAccountToken} and deleted_at is null`;
        const athlete = exists
          ? await lockAthlete(sql, String(exists.id))
          : null;
        await sql`select pg_advisory_xact_lock(hashtextextended(${id.data},3))`;
        const [seen] =
          await sql`select id from apple_notifications where id=${id.data}`;
        if (seen) return;
        if (athlete)
          await apply(sql, athlete, txn, { type, signedDate, renewal });
        // Unknown/deleted accounts never get recreated by an Apple notification.
        await sql`insert into apple_notifications (id,athlete_id,type) values (${id.data},${athlete ? String(athlete.id) : null},${type})`;
      });
    },
  };
}
