import { createHash } from "node:crypto";
import type postgres from "postgres";
import { ApiError } from "../api/errors";

export type Query = postgres.Sql | postgres.TransactionSql;
export type Tx = postgres.TransactionSql;
export type Row = Record<string, unknown>;
export const snake = (key: string) =>
  key.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);
const camel = (key: string) =>
  key.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());
const decimals = new Set([
  "run_priority_weight",
  "strength_priority_weight",
  "target_value",
  "load_kg",
  "load_percent_e1rm",
  "rpe",
  "rir",
  "rpe_min",
  "rpe_max",
  "rir_min",
  "rir_max",
  "session_rpe",
  "pace_min_s_per_km",
  "pace_max_s_per_km",
  "elevation_gain_m",
  "avg_cadence_spm",
  "match_confidence",
]);
export function wire(row: Row): Row {
  return Object.fromEntries(
    Object.entries(row)
      .filter(([key]) => key !== "auth_user_id")
      .map(([key, value]) => [
        camel(key),
        value instanceof Date
          ? [
              "start_date",
              "end_date",
              "target_date",
              "local_date",
              "scheduled_date",
              "training_date",
              "period_start",
              "period_end",
              "date",
            ].includes(key)
            ? value.toISOString().slice(0, 10)
            : value.toISOString()
          : decimals.has(key) && value != null
            ? Number(value)
            : typeof value === "bigint"
              ? String(value)
              : value,
      ]),
  );
}
export function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value !== null && typeof value === "object")
    return `{${Object.entries(value)
      .filter(([, v]) => v !== undefined)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([k, v]) => `${JSON.stringify(k)}:${stableJson(v)}`)
      .join(",")}}`;
  return JSON.stringify(value);
}
export const hash = (value: unknown) =>
  createHash("sha256").update(stableJson(value)).digest("hex");
export function values(sql: Query, data: Row) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [
      snake(key),
      value !== null && typeof value === "object" && !(value instanceof Date)
        ? sql.json(JSON.parse(JSON.stringify(value)))
        : value,
    ]),
  ) as Record<string, postgres.ParameterOrFragment<never>>;
}
export async function insertRow(sql: Query, table: string, data: Row) {
  const [row] = await sql<
    Row[]
  >`insert into ${sql(table)} ${sql(values(sql, data))} returning *`;
  if (!row) throw new Error("Insert did not return a record");
  return row;
}
export async function updateRow(
  sql: Query,
  table: string,
  id: string,
  data: Row,
) {
  const [row] = await sql<
    Row[]
  >`update ${sql(table)} set ${sql(values(sql, data))} where id=${id} returning *`;
  if (!row) throw new ApiError(404, "NOT_FOUND", "The record is unavailable.");
  return row;
}
export async function owned(
  sql: Query,
  table: string,
  id: string,
  athleteId: string,
  allowDeleted = false,
) {
  const [row] = await sql<
    Row[]
  >`select * from ${sql(table)} where id=${id} and athlete_id=${athleteId}`;
  if (!row || (!allowDeleted && row.deleted_at))
    throw new ApiError(
      404,
      "REFERENCE_UNAVAILABLE",
      "A referenced record is unavailable.",
    );
  return row;
}
export async function catalogReference(
  sql: Query,
  table: "exercises" | "equipment",
  id: string,
) {
  const [row] = await sql`select id from ${sql(table)} where id=${id}`;
  if (!row)
    throw new ApiError(400, "INVALID_REFERENCE", "Unknown catalog reference.");
}
export async function lockAthlete(sql: Tx, athleteId: string) {
  await sql`select pg_advisory_xact_lock(hashtextextended(${athleteId}, 0))`;
  const [row] = await sql<
    Row[]
  >`select * from athletes where id=${athleteId} and deleted_at is null for update`;
  if (!row)
    throw new ApiError(
      403,
      "ATHLETE_UNAVAILABLE",
      "The athlete account is unavailable.",
    );
  return row;
}
export async function withAthlete<T>(
  client: postgres.Sql,
  authUserId: string,
  fn: (sql: Tx, athlete: Row) => Promise<T>,
): Promise<T> {
  const [row] =
    await client`select id from athletes where auth_user_id=${authUserId} and deleted_at is null`;
  if (!row)
    throw new ApiError(
      403,
      "ATHLETE_UNAVAILABLE",
      "The athlete account is unavailable.",
    );
  return client.begin(async (sql) =>
    fn(sql, await lockAthlete(sql, String(row.id))),
  ) as Promise<T>;
}
export async function emit(
  sql: Query,
  athleteId: string,
  entityType: string,
  entityId: string,
  operation: "upsert" | "delete",
  revision: string | null,
) {
  const [event] =
    await sql`insert into sync_change_log (athlete_id,entity_type,entity_id,operation,row_revision) values (${athleteId},${entityType},${entityId},${operation},${revision}) returning sequence::text`;
  if (
    entityType === "workout_result" ||
    entityType === "activity_source_record"
  )
    await sql`insert into progress_outbox (athlete_id,sequence) values (${athleteId},${String(event?.sequence)}) on conflict (athlete_id) do update set sequence=greatest(progress_outbox.sequence,excluded.sequence)`;
  return String(event?.sequence);
}
export async function ensureInitialChange(sql: Tx, athlete: Row) {
  const [has] =
    await sql`select sequence from sync_change_log where athlete_id=${String(athlete.id)} and entity_type='athlete' limit 1`;
  if (!has)
    await emit(
      sql,
      String(athlete.id),
      "athlete",
      String(athlete.id),
      "upsert",
      String(athlete.revision),
    );
}
