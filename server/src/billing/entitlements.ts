import { EntitlementSchema } from "../api/schemas";
import { emit, type Tx } from "../db/store";

// Recompute from the newest transaction in every original subscription chain.
// Different chains may overlap (for example after an account's resubscription).
async function refreshStorekit(sql: Tx, athleteId: string) {
  const rows =
    await sql`select * from storekit_transactions where athlete_id=${athleteId} order by original_transaction_id,purchased_at desc,signed_at desc,expires_at desc`;
  const heads = new Map<string, (typeof rows)[number]>(),
    keys = new Set<string>();
  for (const row of rows) {
    keys.add(row.entitlement_key);
    if (!heads.has(row.original_transaction_id))
      heads.set(row.original_transaction_id, row);
  }
  for (const key of keys) {
    const current = [...heads.values()].filter(
        (row) => row.entitlement_key === key,
      ),
      now = Date.now();
    const active = current
      .filter((row) => !row.revoked_at && row.expires_at.getTime() > now)
      .sort((a, b) => b.expires_at.getTime() - a.expires_at.getTime())[0];
    const grace = current
      .filter((row) => !row.revoked_at && row.grace_until?.getTime() > now)
      .sort((a, b) => b.grace_until.getTime() - a.grace_until.getTime())[0];
    const latest =
      current.sort(
        (a, b) => b.purchased_at.getTime() - a.purchased_at.getTime(),
      )[0] ?? rows.find((row) => row.entitlement_key === key);
    if (!latest) continue;
    const status = active
      ? "active"
      : grace
        ? "grace"
        : current.length && latest.revoked_at
          ? "revoked"
          : "expired";
    const validUntil =
      active?.expires_at ?? grace?.grace_until ?? latest.expires_at;
    const [prior] =
      await sql`select * from entitlements where athlete_id=${athleteId} and entitlement_key=${key}`;
    if (
      !prior ||
      prior.status !== status ||
      prior.valid_until?.getTime() !== validUntil.getTime() ||
      prior.source !== "storekit"
    ) {
      const [row] =
        await sql`insert into entitlements (athlete_id,entitlement_key,status,valid_until,source) values (${athleteId},${key},${status},${validUntil},'storekit') on conflict(athlete_id,entitlement_key) do update set status=excluded.status,valid_until=excluded.valid_until,source='storekit',revision=entitlements.revision+1,updated_at=now() returning *`;
      await emit(
        sql,
        athleteId,
        "entitlement",
        String(row?.id),
        "upsert",
        String(row?.revision),
      );
    }
  }
}
export async function effectiveEntitlements(sql: Tx, athleteId: string) {
  await refreshStorekit(sql, athleteId);
  const expired =
    await sql`update entitlements set status='expired',revision=revision+1,updated_at=now() where athlete_id=${athleteId} and source<>'storekit' and status in ('active','grace') and valid_until<=now() returning *`;
  for (const row of expired)
    await emit(
      sql,
      athleteId,
      "entitlement",
      String(row.id),
      "upsert",
      String(row.revision),
    );
  const rows =
    await sql`select * from entitlements where athlete_id=${athleteId} order by entitlement_key`;
  return rows.map((row) =>
    EntitlementSchema.parse({
      key: row.entitlement_key,
      status: row.status,
      validUntil: row.valid_until?.toISOString() ?? null,
    }),
  );
}
