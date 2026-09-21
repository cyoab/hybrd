import { z } from "zod";
import { seedCatalog } from "../catalog/service";
import { readEnv } from "../config/env";
import { PolicyConfigSchema, policyChecksum } from "../config/policy";
import { createDatabase } from "../db/client";
import { emit, lockAthlete } from "../db/store";
import { apnsProvider } from "../notifications/provider";
import { notificationServices } from "../notifications/service";

const [command, ...args] = process.argv.slice(2),
  env = readEnv(),
  database = createDatabase(env.DATABASE_URL);
try {
  if (command === "seed-catalog") {
    await seedCatalog(database.client);
    console.info("Catalog seeded.");
  } else if (command === "publish-policy") {
    const path = args[0];
    if (!path) throw new Error("Usage: ops publish-policy <policy.json>");
    const input = z
      .object({
        config: PolicyConfigSchema,
        minimumAppVersion: z
          .string()
          .regex(/^\d+\.\d+\.\d+$/)
          .nullable()
          .default(null),
      })
      .strict()
      .parse(await Bun.file(path).json());
    const version = await database.client.begin(async (sql) => {
      await sql`select pg_advisory_xact_lock(hashtextextended('training_policy_publication',4))`;
      const [last] =
        await sql`select coalesce(max(version),0)+1 as next from training_policy_versions`;
      // Prior published policies remain immutable and resolvable from saved plans.
      await sql`update training_policy_versions set status='retired' where status='published'`;
      await sql`insert into training_policy_versions (version,schema_version,status,config,checksum,minimum_app_version,published_at) values (${Number(last?.next)},1,'published',${sql.json(input.config)},${policyChecksum(input.config)},${input.minimumAppVersion},now())`;
      return Number(last?.next);
    });
    console.info(`Published policy ${version}.`);
  } else if (command === "grant-dev-entitlement") {
    if (!["development", "test"].includes(env.NODE_ENV))
      throw new Error(
        "Development entitlements cannot be granted in production.",
      );
    const athleteId = z.uuid().parse(args[0]),
      key = z
        .string()
        .min(1)
        .max(64)
        .parse(args[1] ?? env.AI_REQUIRED_ENTITLEMENT);
    await database.client.begin(async (sql) => {
      await lockAthlete(sql, athleteId);
      const [row] =
        await sql`insert into entitlements (athlete_id,entitlement_key,status,valid_until,source) values (${athleteId},${key},'active',now()+interval '7 days','development') on conflict(athlete_id,entitlement_key) do update set status='active',valid_until=excluded.valid_until,source='development',revision=entitlements.revision+1,updated_at=now() returning *`;
      await emit(
        sql,
        athleteId,
        "entitlement",
        String(row?.id),
        "upsert",
        String(row?.revision),
      );
    });
    console.info("Granted seven-day development entitlement.");
  } else if (command === "notify") {
    const authUserId = z.string().min(1).parse(args[0]),
      deviceId = z.uuid().parse(args[1]),
      id = z.uuid().parse(args[2]),
      kind = z.enum(["sync_hint", "coach_ready"]).parse(args[3]);
    console.info(
      await notificationServices(database.client, apnsProvider(env)).send(
        authUserId,
        deviceId,
        id,
        kind,
      ),
    );
  } else if (command === "prune-operational-data") {
    // Sync ledgers/feed and canonical history are intentionally not pruned: offline devices retain replay safety.
    await database.client.begin(async (sql) => {
      await sql`update ai_invocations set context_snapshot_id=null where created_at<now()-interval '30 days' and context_snapshot_id is not null`;
      await sql`delete from intelligence_context_snapshots where created_at<now()-interval '30 days' and id not in (select context_snapshot_id from ai_invocations where context_snapshot_id is not null)`;
      await sql`update ai_invocations set response=null where created_at<now()-interval '90 days' and response is not null`;
      await sql`delete from apple_notifications where received_at<now()-interval '90 days'`;
    });
    console.info(
      "Expired operational payloads pruned. Canonical training data retained.",
    );
  } else
    throw new Error(
      "Commands: seed-catalog, publish-policy, grant-dev-entitlement, notify, prune-operational-data",
    );
} finally {
  await database.close();
}
