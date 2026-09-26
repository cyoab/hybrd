import { expect, test } from "bun:test";
import { emit, withAthlete } from "../../src/db/store";
import { actualQueries } from "../../src/progress/projection";
import { SummarySchema } from "../../src/progress/schemas";
import { harness } from "../integration/helpers";

// Explicit opt-in; never runs in the normal unit/integration suite or against the dev database.
test("10,000-result authenticated progress benchmark", async () => {
  const h = harness({
    progress: { now: () => new Date("2026-10-31T16:00:00Z") },
  });
  const a = await h.account();
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch: h.app.fetch,
  });
  try {
    await withAthlete(h.database.client, a.userId, async (sql) => {
      await sql`insert into workout_results (id,athlete_id,discipline,training_date,timezone,completion_status,source_type,duration_s)
        select gen_random_uuid(),${a.athleteId}::uuid,case when i%2=0 then 'running' else 'strength' end,
          date '2026-10-31'-(i/3), 'America/Monterrey','completed','manual',null from generate_series(0,9999) i`;
      await sql`insert into run_results (workout_result_id,distance_m,duration_s,hr_zone_summary)
        select id,5000,1800,'[]'::jsonb from workout_results where athlete_id=${a.athleteId} and discipline='running'`;
      await sql`update workout_results set duration_s=1800 where athlete_id=${a.athleteId} and discipline='strength'`;
      await sql`insert into strength_exercise_results (id,workout_result_id,exercise_id,sequence)
        select gen_random_uuid(),id,'10000000-0000-4000-8003-000000000000',0 from workout_results where athlete_id=${a.athleteId} and discipline='strength'`;
      await sql`insert into strength_set_results (id,exercise_result_id,set_number,set_kind,reps,load_kg,status)
        select gen_random_uuid(),e.id,i,'working',5,60,'completed' from strength_exercise_results e join workout_results r on r.id=e.workout_result_id
        cross join generate_series(1,12) i where r.athlete_id=${a.athleteId}`;
      await sql`insert into activity_source_records (id,athlete_id,provider,external_id,fingerprint,workout_result_id,import_status,match_status,metadata)
        select gen_random_uuid(),${a.athleteId}::uuid,'healthkit',gen_random_uuid()::text,gen_random_uuid()::text,r.id,'imported','confirmed','{}'::jsonb
        from workout_results r cross join generate_series(1,2) i where r.athlete_id=${a.athleteId} and r.discipline='running'`;
      await sql`insert into sync_change_log (athlete_id,entity_type,entity_id,operation,row_revision)
        select athlete_id,'workout_result',id,'upsert',revision from workout_results where athlete_id=${a.athleteId}
        union all select athlete_id,'activity_source_record',id,'upsert',revision from activity_source_records where athlete_id=${a.athleteId}`;
      await sql`insert into progress_outbox (athlete_id,sequence) select ${a.athleteId}::uuid,max(sequence) from sync_change_log where athlete_id=${a.athleteId}`;
    });
    for (const table of [
      "workout_results",
      "run_results",
      "strength_exercise_results",
      "strength_set_results",
      "activity_source_records",
      "sync_change_log",
    ])
      await h.database.client`analyze ${h.database.client(table)}`;
    const path =
      "/v1/progress/summary?periodDays=84&timezone=America/Monterrey";
    const cold: number[] = [],
      cached: number[] = [];
    const request = async () => {
      const start = performance.now();
      const response = await fetch(new URL(path, server.url), {
        headers: { ...a.headers, "accept-encoding": "gzip" },
      });
      const body = SummarySchema.parse(await response.json());
      expect(response.status).toBe(200);
      expect(response.headers.get("content-encoding")).toBe("gzip");
      expect(body.totals.lifetime.sessions).toBe(10000);
      expect(body.totals.lifetime.strengthSets).toBe(60000);
      expect(body.totals.lifetime.runMeters).toBe(25000000);
      return performance.now() - start;
    };
    const initialBuildMs = Math.round(await request());
    for (let i = 0; i < 20; i++) {
      await withAthlete(h.database.client, a.userId, async (sql) => {
        const [changed] =
          await sql`update workout_results set revision=revision+1,updated_at=clock_timestamp()
          where id=(select id from workout_results where athlete_id=${a.athleteId} and discipline='running' order by training_date desc,id limit 1)
          returning id,revision::text`;
        await sql`update run_results set duration_s=${1801 + i} where workout_result_id=${String(changed?.id)}`;
        await emit(
          sql,
          a.athleteId,
          "workout_result",
          String(changed?.id),
          "upsert",
          String(changed?.revision),
        );
      });
      cold.push(await request());
    }
    for (let i = 0; i < 50; i++) cached.push(await request());
    const compressed = await h.app.request(path, {
      headers: { ...a.headers, "accept-encoding": "gzip" },
    });
    const compressedBytes = (await compressed.arrayBuffer()).byteLength;
    expect(compressedBytes).toBeLessThanOrEqual(30 * 1024);
    const quantiles = (values: number[]) => {
      const sorted = [...values].sort((a, b) => a - b);
      return {
        samples: values.length,
        p50Ms: Math.round(sorted[Math.ceil(sorted.length * 0.5) - 1] ?? 0),
        p95Ms: Math.round(sorted[Math.ceil(sorted.length * 0.95) - 1] ?? 0),
        maxMs: Math.round(sorted.at(-1) ?? 0),
      };
    };
    const canonicalPlans = await withAthlete(
      h.database.client,
      a.userId,
      async (sql) => {
        const plans = await Promise.all(
          actualQueries(sql, a.athleteId, new Date("2026-10-31T16:00:00Z")).map(
            (query) => sql`explain (analyze,buffers,format json) ${query}`,
          ),
        );
        return {
          results: plans[0]?.[0]?.["QUERY PLAN"],
          sets: plans[1]?.[0]?.["QUERY PLAN"],
          sources: plans[2]?.[0]?.["QUERY PLAN"],
        };
      },
    );
    const activityPlan = await h.database
      .client`explain (analyze,buffers,format json) select payload from progress_activity
      where athlete_id=${a.athleteId} and date between '2026-08-09' and '2026-10-31' order by date desc,result_id desc limit 51`;
    const report = {
      generatedAt: new Date().toISOString(),
      environment:
        "Docker Compose, Bun HTTP loopback + real auth/PostgreSQL 17, gzip; single athlete and serial requests; warm DB pages; cold includes complete canonical recalculation and changed-row projection persistence after an edit",
      results: 10000,
      completedSets: 60000,
      sourceRecords: 10000,
      initialBuildMs,
      cold: quantiles(cold),
      cached: quantiles(cached),
      compressedBytes,
      canonicalPlans,
      activityPlan: activityPlan[0]?.["QUERY PLAN"],
    };
    console.info(JSON.stringify(report, null, 2));
    if (process.env.PROGRESS_BENCH_REPORT)
      await Bun.write(
        process.env.PROGRESS_BENCH_REPORT,
        `${JSON.stringify(report, null, 2)}\n`,
      );
  } finally {
    server.stop(true);
    await h.close();
  }
}, 120000);
