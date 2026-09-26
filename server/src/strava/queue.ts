import type { Query, Tx } from "../db/store";
import { StravaError } from "./provider";

export async function queueWorkout(
  sql: Tx,
  athleteId: string,
  workoutId: string,
) {
  // In the same transaction as the workout: rolled-back/replayed sync never
  // causes an external publish. Imported HealthKit activities cannot loop back.
  await sql`insert into strava_jobs (athlete_id,generation,kind,workout_id,logical_workout_id)
    select c.athlete_id,c.generation,'publish',w.id,w.logical_workout_id from strava_connections c
    join workout_results w on w.athlete_id=c.athlete_id
    where c.athlete_id=${athleteId} and w.id=${workoutId} and c.status='connected' and c.auto_publish
      and w.source_type='manual' and w.completion_status in ('completed','partial','modified') and w.deleted_at is null
    on conflict do nothing`;
  await sql`update strava_jobs j set workout_id=w.id,
    state=case when w.source_type='manual' and w.completion_status in ('completed','partial','modified') and w.deleted_at is null then 'queued' else 'cancelled' end,
    available_at=now(),error_code=null,updated_at=now()
    from workout_results w,strava_connections c where w.id=${workoutId} and w.athlete_id=${athleteId} and c.athlete_id=w.athlete_id
    and j.athlete_id=w.athlete_id and (j.workout_id=w.id or j.logical_workout_id=w.logical_workout_id)
    and j.state in ('queued','retry','needs_details') and j.payload is null and j.generation=c.generation and c.status='connected' and c.auto_publish`;
}

// Stay below the default application-wide overall AND read quotas. Reserve
// before each request, including refresh, to coordinate API and worker calls.
export async function reserveRequest(client: Query) {
  const rows =
    await client`insert into strava_budget (id,short_start,short_count,day_start,day_count)
    values (1,date_bin(interval '15 minutes',now(),'2000-01-01'::timestamptz),1,date_trunc('day',now() at time zone 'UTC') at time zone 'UTC',1)
    on conflict(id) do update set
      short_start=excluded.short_start,
      short_count=case when strava_budget.short_start<excluded.short_start then 1 else strava_budget.short_count+1 end,
      day_start=excluded.day_start,
      day_count=case when strava_budget.day_start<excluded.day_start then 1 else strava_budget.day_count+1 end
    where (strava_budget.blocked_until is null or strava_budget.blocked_until<=now())
      and (strava_budget.short_start<excluded.short_start or strava_budget.short_count<80)
      and (strava_budget.day_start<excluded.day_start or strava_budget.day_count<800)
    returning id`;
  if (!rows.length) throw new StravaError("STRAVA_RATE_LIMITED", 900);
}
