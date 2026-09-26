import type { Row, Tx } from "../db/store";
import { type Actual, type Projection, project, type SetGroup } from "./engine";
import { RULES_VERSION } from "./schemas";

const instant = (v: unknown): string | null =>
  v == null ? null : new Date(String(v)).toISOString();
const day = (v: unknown) =>
  v instanceof Date ? v.toISOString().slice(0, 10) : String(v);
// Shared by the loader and EXPLAIN benchmark so measured plans cannot drift from production SQL.
export function actualQueries(sql: Tx, athleteId: string, now: Date) {
  return [
    sql`with changes as (
        select entity_id,max(sequence) as sequence from sync_change_log
        where athlete_id=${athleteId} and entity_type='workout_result' group by entity_id
      ) select r.*, coalesce(ch.sequence,0)::text as canonical_sequence, w.title, w.workout_type, run.distance_m, run.duration_s as run_duration_s
      from workout_results r
      left join changes ch on ch.entity_id=r.id
      left join planned_workouts w on w.id=r.planned_workout_id
      left join run_results run on run.workout_result_id=r.id
      where r.athlete_id=${athleteId} and r.deleted_at is null`,
    sql`select workout_result_id, exercise_id, exercise_name, reps, load_convention,
      count(*) filter (where valid)::int as count, max(load_kg) filter (where valid)::float8 as load_kg,
      count(*) filter (where not valid)::int as excluded,
      min(completed_at) filter (where completed_at>${now}) as next_set_at
      from (
        select e.workout_result_id, e.exercise_id, c.name as exercise_name, s.*,
          coalesce(s.status='completed' and s.reps between 1 and 100 and s.load_kg between 0 and 1000
            and trim(c.name)<>'' and (s.completed_at is null or s.completed_at<=${now}),false) as valid
        from workout_results r join strength_exercise_results e on e.workout_result_id=r.id
        join strength_set_results s on s.exercise_result_id=e.id join exercises c on c.id=e.exercise_id
        where r.athlete_id=${athleteId} and r.deleted_at is null
      ) v group by workout_result_id,exercise_id,exercise_name,reps,load_convention`,
    sql`select workout_result_id, count(*)::int as records,
      count(*) filter (where deleted_at is null and source_deleted_at is null and match_status in ('unmatched','suggested'))::int as unresolved,
      count(*) filter (where deleted_at is not null or source_deleted_at is not null)::int as deleted
      from activity_source_records where athlete_id=${athleteId} group by workout_result_id`,
  ] as const;
}
export async function loadActuals(sql: Tx, athleteId: string, now: Date) {
  const [roots, sets, sources] = await Promise.all(
    actualQueries(sql, athleteId, now),
  );
  const setsByResult = new Map<
    string,
    { sets: SetGroup[]; excluded: number; next: string | null }
  >();
  for (const s of sets) {
    const id = String(s.workout_result_id),
      entry = setsByResult.get(id) ?? { sets: [], excluded: 0, next: null };
    if (Number(s.count) > 0)
      entry.sets.push({
        exerciseId: String(s.exercise_id),
        exerciseName: String(s.exercise_name),
        reps: Number(s.reps),
        loadConvention: String(s.load_convention),
        count: Number(s.count),
        loadKg: Number(s.load_kg),
      });
    entry.excluded += Number(s.excluded);
    const next = instant(s.next_set_at);
    if (next && (!entry.next || next < entry.next)) entry.next = next;
    setsByResult.set(id, entry);
  }
  const sourcesByResult = new Map(
    sources.map((s) => [String(s.workout_result_id), s]),
  );
  const actuals: Actual[] = roots.map((r) => {
    const set = setsByResult.get(String(r.id)),
      source = sourcesByResult.get(String(r.id));
    return {
      id: String(r.id),
      canonicalSequence: String(r.canonical_sequence),
      revision: String(r.revision),
      logicalId: r.logical_workout_id ? String(r.logical_workout_id) : null,
      updatedAt: instant(r.updated_at) as string,
      trainingDate: day(r.training_date),
      timezone: String(r.timezone),
      dateBasis: r.date_basis as Actual["dateBasis"],
      loggedAt: instant(r.logged_at),
      startedAt: instant(r.started_at),
      endedAt: instant(r.ended_at),
      discipline: r.discipline as Actual["discipline"],
      completionStatus: String(r.completion_status),
      sourceType: String(r.source_type),
      title: r.title == null ? null : String(r.title),
      runType: r.workout_type == null ? null : String(r.workout_type),
      distanceM: r.distance_m == null ? null : Number(r.distance_m),
      runDurationS: r.run_duration_s == null ? null : Number(r.run_duration_s),
      durationS: r.duration_s == null ? null : Number(r.duration_s),
      sets: set?.sets ?? [],
      excludedSets: set?.excluded ?? 0,
      nextSetAt: set?.next ?? null,
      sources: Number(source?.records ?? 0),
      unresolvedSources: Number(source?.unresolved ?? 0),
      deletedSources: Number(source?.deleted ?? 0),
    };
  });
  return {
    actuals,
    unlinkedSources: Number(sourcesByResult.get("null")?.unresolved ?? 0),
  };
}

export type ProjectionState = {
  sequence: string;
  generation: string;
  projectedAt: string;
  refreshAfter: string | null;
  metadata: Projection["metadata"];
};
const stateFrom = (r: Row): ProjectionState => ({
  sequence: String(r.sequence),
  generation: String(r.generation),
  projectedAt: instant(r.projected_at) as string,
  refreshAfter: instant(r.refresh_after),
  metadata: r.metadata as Projection["metadata"],
});

// Caller holds the athlete lock shared with sync. State, projections, caches and job acknowledgement commit together.
export async function ensureProjection(
  sql: Tx,
  athleteId: string,
  now: Date,
): Promise<ProjectionState> {
  const [existing] =
    await sql`select * from progress_state where athlete_id=${athleteId}`;
  const [pending] =
    await sql`select sequence::text from progress_outbox where athlete_id=${athleteId}`;
  const due =
    existing?.refresh_after &&
    new Date(existing.refresh_after).getTime() <= now.getTime();
  if (
    existing &&
    existing.rules_version === RULES_VERSION &&
    !due &&
    (!pending || BigInt(pending.sequence) <= BigInt(existing.sequence))
  ) {
    if (pending)
      await sql`delete from progress_outbox where athlete_id=${athleteId} and sequence<=${String(existing.sequence)}`;
    return stateFrom(existing);
  }
  const [watermark] =
    await sql`select coalesce(max(sequence),0)::text as value from sync_change_log
    where athlete_id=${athleteId} and entity_type in ('workout_result','activity_source_record')`;
  const sequence = String(watermark?.value ?? "0");
  const { actuals, unlinkedSources } = await loadActuals(sql, athleteId, now);
  const projection = project(actuals, athleteId, now);
  projection.metadata.exclusions.unlinkedSources = unlinkedSources;
  const generation = crypto.randomUUID();
  // Recompute globally, but only write changed rows. This avoids rewriting years of
  // unchanged activity and generating dead tuples whenever one workout is corrected.
  await sql`delete from progress_days where athlete_id=${athleteId} and not (date=any(${projection.days.map((d) => d.date)}::date[]))`;
  await sql`delete from progress_activity where athlete_id=${athleteId} and not (result_id=any(${projection.activities.map((a) => a.resultId)}::uuid[]))`;
  await sql`delete from progress_comparisons where athlete_id=${athleteId} and not (key=any(${projection.groups.map((g) => g.key)}::text[]))`;
  if (projection.days.length)
    await sql`insert into progress_days (athlete_id,date,totals)
    select ${athleteId}::uuid, (v->>'date')::date, v from jsonb_array_elements(${sql.json(projection.days)}) v
    on conflict (athlete_id,date) do update set totals=excluded.totals where progress_days.totals is distinct from excluded.totals`;
  if (projection.activities.length)
    await sql`insert into progress_activity (athlete_id,result_id,date,payload)
    select ${athleteId}::uuid, (v->>'resultId')::uuid, (v->>'trainingDate')::date, v from jsonb_array_elements(${sql.json(projection.activities)}) v
    on conflict (athlete_id,result_id) do update set date=excluded.date,payload=excluded.payload where progress_activity.payload is distinct from excluded.payload`;
  if (projection.groups.length)
    await sql`insert into progress_comparisons (athlete_id,key,payload)
    select ${athleteId}::uuid, v->>'key', v from jsonb_array_elements(${sql.json(projection.groups)}) v
    on conflict (athlete_id,key) do update set payload=excluded.payload where progress_comparisons.payload is distinct from excluded.payload`;
  await sql`insert into progress_state (athlete_id,sequence,rules_version,generation,projected_at,refresh_after,metadata)
    values (${athleteId},${sequence},${RULES_VERSION},${generation},${now},${projection.refreshAfter},${sql.json(projection.metadata)})
    on conflict(athlete_id) do update set sequence=excluded.sequence,rules_version=excluded.rules_version,generation=excluded.generation,
      projected_at=excluded.projected_at,refresh_after=excluded.refresh_after,metadata=excluded.metadata`;
  await sql`delete from progress_cache where athlete_id=${athleteId}`;
  await sql`delete from progress_outbox where athlete_id=${athleteId} and sequence<=${sequence}`;
  return {
    sequence,
    generation,
    projectedAt: now.toISOString(),
    refreshAfter: projection.refreshAfter,
    metadata: projection.metadata,
  };
}
