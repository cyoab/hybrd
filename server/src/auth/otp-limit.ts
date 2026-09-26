import { createHmac } from "node:crypto";
import { sql } from "drizzle-orm";
import type { Database } from "../db/client";

export function authDigest(secret: string, value: string) {
  return createHmac("sha256", secret).update(value).digest("hex");
}

// A reservation is taken before rotating/sending the code, even if delivery fails.
// The atomic upsert also works when requests arrive at different API instances.
export async function reserveOtpSend(
  db: Database,
  secret: string,
  email: string,
): Promise<number> {
  const key = authDigest(secret, `otp-email:${email}`);
  await db.execute(
    sql`delete from auth_otp_throttle where window_start < now() - interval '1 hour'`,
  );
  const rows = await db.execute(sql`
    insert into auth_otp_throttle (key, window_start, last_sent_at, send_count)
    values (${key}, now(), now(), 1)
    on conflict (key) do update set last_sent_at = now(), send_count = auth_otp_throttle.send_count + 1
    where auth_otp_throttle.last_sent_at <= now() - interval '60 seconds'
      and auth_otp_throttle.send_count < 3
    returning key`);
  if (rows.length) return 0;
  const [limit] = await db.execute(sql`
    select greatest(1, ceil(extract(epoch from (
      case when send_count >= 3 then window_start + interval '1 hour'
      else last_sent_at + interval '60 seconds' end - now()))))::integer as retry
    from auth_otp_throttle where key=${key}`);
  return Number(limit?.retry ?? 60);
}
