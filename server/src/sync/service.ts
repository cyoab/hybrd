import type postgres from "postgres";
import { ZodError } from "zod";
import { ApiError } from "../api/errors";
import { effectiveEntitlements } from "../billing/entitlements";
import {
  ensureInitialChange,
  hash,
  type Row,
  type Tx,
  withAthlete,
} from "../db/store";
import { type EntityType, entityTables, readEntity } from "../domain/read";
import { applyMutation } from "./mutations";
import {
  type MutationResult,
  type Pull,
  type Push,
  SyncPullQuerySchema,
  SyncPullResponse,
  SyncPushSchema,
} from "./schemas";

export async function requireDevice(
  sql: Tx,
  athleteId: string,
  deviceId: string,
) {
  const [device] =
    await sql`select id from device_installations where id=${deviceId} and athlete_id=${athleteId} and revoked_at is null`;
  if (!device)
    throw new ApiError(
      403,
      "DEVICE_UNAVAILABLE",
      "Register this installation before syncing.",
    );
}
export function syncServices(client: postgres.Sql) {
  return {
    push: async (authUserId: string, request: Push) => {
      const input = SyncPushSchema.parse(request),
        results: MutationResult[] = [];
      for (const mutation of input.mutations)
        results.push(
          await withAthlete(client, authUserId, async (sql, athlete) => {
            const athleteId = String(athlete.id);
            await requireDevice(sql, athleteId, input.deviceId);
            await ensureInitialChange(sql, athlete);
            await sql`select pg_advisory_xact_lock(hashtextextended(${mutation.id},1))`;
            const fingerprint = hash(mutation);
            const [prior] =
              await sql`select * from sync_mutations where client_mutation_id=${mutation.id}`;
            if (prior) {
              if (
                prior.athlete_id !== athleteId ||
                prior.request_hash !== fingerprint
              )
                return {
                  mutationId: mutation.id,
                  status: "rejected" as const,
                  error: {
                    code: "IDEMPOTENCY_KEY_REUSED",
                    message: "Use a new mutation ID for different content.",
                  },
                };
              return prior.result as MutationResult;
            }
            let outcome: MutationResult;
            try {
              const entityRevision = await sql.savepoint((tx) =>
                applyMutation(tx, athlete, mutation),
              );
              outcome = {
                mutationId: mutation.id,
                status: "applied",
                entityRevision,
              };
            } catch (error) {
              if (
                !(error instanceof ApiError) &&
                !(error instanceof ZodError) &&
                !(
                  error instanceof Error &&
                  "code" in error &&
                  ["23505", "23503", "23514", "22003"].includes(
                    String(error.code),
                  )
                )
              )
                throw error;
              const conflict =
                error instanceof ApiError && error.status === 409;
              outcome = {
                mutationId: mutation.id,
                status: conflict ? "conflict" : "rejected",
                error: {
                  code:
                    error instanceof ApiError
                      ? error.code
                      : error instanceof ZodError
                        ? "VALIDATION_ERROR"
                        : "CONSTRAINT_VIOLATION",
                  message:
                    error instanceof ApiError
                      ? error.message
                      : "The mutation violates the data contract.",
                },
              };
            }
            await sql`insert into sync_mutations (client_mutation_id,athlete_id,device_id,entity_type,entity_id,operation,request_hash,status,result) values (${mutation.id},${athleteId},${input.deviceId},${mutation.entityType},${mutation.entityId},${mutation.operation},${fingerprint},${outcome.status},${sql.json(outcome)})`;
            await sql`insert into device_sync_state (device_id,athlete_id,last_push_at) values (${input.deviceId},${athleteId},now()) on conflict(device_id) do update set last_push_at=now(),updated_at=now()`;
            return outcome;
          }),
        );
      const serverSequence = await withAthlete(
        client,
        authUserId,
        async (sql, athlete) => {
          const [row] =
            await sql`select coalesce(max(sequence),0)::text as value from sync_change_log where athlete_id=${String(athlete.id)}`;
          return String(row?.value ?? "0");
        },
      );
      return { results, serverSequence };
    },
    pull: async (authUserId: string, request: Pull) => {
      const input = SyncPullQuerySchema.parse(request);
      return withAthlete(client, authUserId, async (sql, athlete) => {
        const athleteId = String(athlete.id);
        await requireDevice(sql, athleteId, input.deviceId);
        await ensureInitialChange(sql, athlete);
        await effectiveEntitlements(sql, athleteId);
        const [latest] =
          await sql`select coalesce(max(sequence),0)::text as value from sync_change_log where athlete_id=${athleteId}`;
        if (BigInt(input.cursor) > BigInt(String(latest?.value ?? "0")))
          throw new ApiError(
            400,
            "CURSOR_AHEAD",
            "Restart the initial pull from cursor zero.",
          );
        const events =
          await sql`select * from sync_change_log where athlete_id=${athleteId} and sequence>${input.cursor} order by sequence limit ${input.limit + 1}`;
        const selected = events.slice(0, input.limit),
          changes = [];
        for (const event of selected) {
          if (!(String(event.entity_type) in entityTables))
            throw new Error("Unknown change-feed entity");
          const payload = await readEntity(
            sql,
            athleteId,
            event.entity_type as EntityType,
            String(event.entity_id),
          );
          const deleted = !payload || Boolean(payload.deletedAt);
          changes.push({
            sequence: String(event.sequence),
            entityType: String(event.entity_type),
            entityId: String(event.entity_id),
            operation: deleted ? ("delete" as const) : ("upsert" as const),
            revision: payload?.revision ? String(payload.revision) : null,
            payload: deleted ? null : payload,
          });
        }
        return SyncPullResponse.parse({
          changes,
          nextCursor: String(selected.at(-1)?.sequence ?? input.cursor),
          hasMore: events.length > input.limit,
        });
      });
    },
    acknowledge: async (authUserId: string, deviceId: string, cursor: string) =>
      withAthlete(client, authUserId, async (sql, athlete) => {
        const athleteId = String(athlete.id);
        await requireDevice(sql, athleteId, deviceId);
        const [latest] =
          await sql`select coalesce(max(sequence),0)::text as value from sync_change_log where athlete_id=${athleteId}`;
        if (BigInt(cursor) > BigInt(String(latest?.value ?? "0")))
          throw new ApiError(
            400,
            "CURSOR_AHEAD",
            "Cannot acknowledge an unknown sequence.",
          );
        await sql`insert into device_sync_state (device_id,athlete_id,last_pulled_sequence) values (${deviceId},${athleteId},${cursor}) on conflict(device_id) do update set last_pulled_sequence=greatest(device_sync_state.last_pulled_sequence,excluded.last_pulled_sequence),updated_at=now()`;
      }),
  };
}
export async function exportTraining(sql: Tx, athlete: Row) {
  await ensureInitialChange(sql, athlete);
  const data: Record<string, unknown> = {};
  for (const [type, table] of Object.entries(entityTables)) {
    const ids =
      type === "athlete"
        ? [{ id: athlete.id }]
        : await sql`select id from ${sql(table)} where athlete_id=${String(athlete.id)} order by id`;
    data[type] = await Promise.all(
      ids.map((row) =>
        readEntity(sql, String(athlete.id), type as EntityType, String(row.id)),
      ),
    );
  }
  return { schemaVersion: 1, exportedAt: new Date().toISOString(), data };
}
