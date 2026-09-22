import type { z } from "@hono/zod-openapi";
import type postgres from "postgres";
import { ApiError } from "../api/errors";
import { hash, type Tx, withAthlete } from "../db/store";
import { addDays, calendar } from "./calendar";
import { cursors } from "./cursor";
import {
  comparison,
  milestoneValue,
  percent,
  pointOrder,
  type StoredGroup,
  series,
  sum,
} from "./engine";
import { ensureProjection, type ProjectionState } from "./projection";
import {
  ActivityPageSchema,
  type ActivityQuery,
  ActivitySchema,
  ComparisonPageSchema,
  type ComparisonQuery,
  type ProgressDay,
  type SummaryQuery,
  SummarySchema,
  type Totals,
} from "./schemas";

export type ProgressOptions = { now?: () => Date };
export function progressServices(
  client: postgres.Sql,
  secret: string,
  options: ProgressOptions = {},
) {
  const clock = options.now ?? (() => new Date()),
    cursor = cursors(secret);
  function context(timezone: string, state: ProjectionState, now: Date) {
    const cal = calendar(timezone),
      today = cal.day(now);
    const expires = Math.min(
      cal.nextMidnight(now).getTime(),
      state.refreshAfter ? Date.parse(state.refreshAfter) : Infinity,
    );
    return { today, expires, timezone, now, state };
  }
  async function metadata(
    sql: Tx,
    athleteId: string,
    ctx: ReturnType<typeof context>,
  ) {
    const basis =
      await sql`select distinct payload->>'dateBasis' as basis from progress_activity where athlete_id=${athleteId} and date<=${ctx.today}`;
    return {
      schemaVersion: 1 as const,
      rulesVersion: 1 as const,
      asOf: ctx.now.toISOString(),
      timezone: ctx.timezone,
      dateBasis:
        basis.length > 1
          ? ("mixed" as const)
          : basis[0]?.basis === "loggedDate"
            ? ("loggedDate" as const)
            : ("performedDate" as const),
      dataRevision: ctx.state.sequence,
      projectionSequence: ctx.state.sequence,
      freshness: "current" as const,
    };
  }
  return {
    summary(authUserId: string, query: z.infer<typeof SummaryQuery>) {
      return withAthlete(client, authUserId, async (sql, athlete) => {
        const athleteId = String(athlete.id),
          now = clock(),
          state = await ensureProjection(sql, athleteId, now);
        const ctx = context(query.timezone, state, now);
        const cacheKey = hash({
          athleteId,
          schemaVersion: 1,
          rulesVersion: 1,
          datePolicy: "stored-local-day-v1",
          ...query,
          today: ctx.today,
          revision: state.sequence,
          generation: state.generation,
        });
        const [cached] =
          await sql`select payload,etag from progress_cache where athlete_id=${athleteId} and key=${cacheKey} and expires_at>${now}`;
        if (cached)
          return {
            body: SummarySchema.parse(cached.payload),
            etag: String(cached.etag),
            expiresAt: new Date(ctx.expires).toISOString(),
          };
        const [days, groupRows, recentRows, meta] = await Promise.all([
          sql`select totals from progress_days where athlete_id=${athleteId} and date<=${ctx.today} order by date`,
          sql`select payload from progress_comparisons where athlete_id=${athleteId}`,
          sql`select payload from progress_activity where athlete_id=${athleteId} and date<=${ctx.today} order by date desc,result_id desc limit 3`,
          metadata(sql, athleteId, ctx),
        ]);
        const allDays = days.map((d) => d.totals as ProgressDay),
          currentDays = series(allDays, ctx.today, query.periodDays);
        const previousEnd = addDays(ctx.today, -query.periodDays),
          previousDays = series(allDays, previousEnd, query.periodDays);
        const current = sum(currentDays),
          previous = sum(previousDays),
          lifetime = sum(allDays);
        const percentChange = Object.fromEntries(
          (Object.keys(current) as (keyof Totals)[]).map((k) => [
            k,
            percent(current[k], previous[k]),
          ]),
        );
        const candidates = groupRows
          .map((g) => comparison(g.payload as StoredGroup, ctx.today))
          .filter((c) => c !== null);
        candidates.sort((a, b) =>
          a.order !== b.order
            ? a.order > b.order
              ? -1
              : 1
            : a.key < b.key
              ? -1
              : 1,
        );
        const comparisons = [
          candidates.find((c) => c.group.kind === "running"),
          candidates.find((c) => c.group.kind === "strength"),
        ].filter((c) => c !== undefined);
        const body = SummarySchema.parse({
          ...meta,
          periodDays: query.periodDays,
          range: {
            startDate: addDays(ctx.today, 1 - query.periodDays),
            endDateInclusive: ctx.today,
            includesPartialToday: true,
            previousStartDate: addDays(previousEnd, 1 - query.periodDays),
            previousEndDateInclusive: previousEnd,
          },
          totals: { current, previous, lifetime, percentChange },
          series: currentDays,
          activityDays: series(allDays, ctx.today, 28),
          journey: {
            trainingDays: lifetime.activeDays,
            level: 1 + Math.floor(lifetime.activeDays / 10),
            stepsInLevel: lifetime.activeDays % 10,
            stepsToNextLevel: 10 - (lifetime.activeDays % 10),
          },
          milestones: state.metadata.milestones.map((m) => ({
            ...m,
            current: milestoneValue(m.unit, lifetime),
            ...(m.earnedOn && m.earnedOn > ctx.today
              ? { earnedOn: null, earnedAt: null, evidenceResultId: null }
              : {}),
          })),
          comparisons,
          recentActivity: recentRows.map((r) => r.payload),
          exclusions: { ...state.metadata.exclusions },
        });
        const [futureDates] =
          await sql`select count(*)::int as count from progress_activity where athlete_id=${athleteId} and date>${ctx.today}`;
        body.exclusions.futureDateResults = Number(futureDates?.count ?? 0);
        const etag = `"progress-${hash({ cacheKey, body })}"`;
        await sql`insert into progress_cache (athlete_id,key,etag,expires_at,payload) values (${athleteId},${cacheKey},${etag},${new Date(ctx.expires)},${sql.json(body)})
          on conflict(athlete_id,key) do update set etag=excluded.etag,expires_at=excluded.expires_at,payload=excluded.payload,created_at=now()`;
        // Bound cache cardinality even when a client sends many valid timezone aliases.
        await sql`delete from progress_cache where athlete_id=${athleteId} and key in
          (select key from progress_cache where athlete_id=${athleteId} order by created_at desc,key limit all offset 12)`;
        return { body, etag, expiresAt: new Date(ctx.expires).toISOString() };
      });
    },
    comparison(
      authUserId: string,
      key: string,
      query: z.infer<typeof ComparisonQuery>,
    ) {
      return withAthlete(client, authUserId, async (sql, athlete) => {
        const athleteId = String(athlete.id),
          now = clock(),
          state = await ensureProjection(sql, athleteId, now);
        const ctx = context(query.timezone, state, now),
          scope = hash({
            athleteId,
            kind: "comparison",
            key,
            timezone: query.timezone,
            limit: query.limit,
          });
        const after = cursor.decode(query.cursor, scope, state.generation, now);
        const [row] =
          await sql`select payload from progress_comparisons where athlete_id=${athleteId} and key=${key}`;
        const stored = row?.payload as StoredGroup | undefined,
          view = stored && comparison(stored, ctx.today);
        if (!view || !stored)
          throw new ApiError(
            404,
            "COMPARISON_UNAVAILABLE",
            "The comparison is unavailable.",
          );
        const points = stored.points
          .filter(
            (p) =>
              p.trainingDate <= ctx.today && (!after || pointOrder(p) > after),
          )
          .slice(0, query.limit + 1);
        const page = points.slice(0, query.limit),
          last = page.at(-1);
        return ComparisonPageSchema.parse({
          ...(await metadata(sql, athleteId, ctx)),
          comparison: view,
          points: page,
          nextCursor:
            points.length > query.limit && last
              ? cursor.encode({
                  scope,
                  generation: state.generation,
                  expires: ctx.expires,
                  after: pointOrder(last),
                })
              : null,
        });
      });
    },
    activity(authUserId: string, query: z.infer<typeof ActivityQuery>) {
      return withAthlete(client, authUserId, async (sql, athlete) => {
        const athleteId = String(athlete.id),
          now = clock(),
          state = await ensureProjection(sql, athleteId, now);
        const ctx = context(query.timezone, state, now),
          scope = hash({
            athleteId,
            kind: "activity",
            timezone: query.timezone,
            limit: query.limit,
            from: query.from,
            to: query.to,
          });
        const after = cursor.decode(query.cursor, scope, state.generation, now);
        const [afterDate, afterId] = after?.split("|") ?? [];
        const rows =
          await sql`select payload from progress_activity where athlete_id=${athleteId} and date between ${query.from} and ${query.to} and date<=${ctx.today}
          ${afterDate && afterId ? sql`and (date,result_id)<(${afterDate}::date,${afterId}::uuid)` : sql``}
          order by date desc,result_id desc limit ${query.limit + 1}`;
        const page = rows
            .slice(0, query.limit)
            .map((r) => ActivitySchema.parse(r.payload)),
          last = page.at(-1);
        return ActivityPageSchema.parse({
          ...(await metadata(sql, athleteId, ctx)),
          activity: page,
          nextCursor:
            rows.length > query.limit && last
              ? cursor.encode({
                  scope,
                  generation: state.generation,
                  expires: ctx.expires,
                  after: `${last.trainingDate}|${last.resultId}`,
                })
              : null,
        });
      });
    },
  };
}
