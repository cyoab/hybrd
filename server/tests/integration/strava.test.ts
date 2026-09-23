import { afterAll, afterEach, beforeEach, expect, test } from "bun:test";
import { readEnv } from "../../src/config/env";
import { unseal } from "../../src/strava/crypto";
import {
  Activity,
  StravaError,
  type StravaProvider,
} from "../../src/strava/provider";
import { processStravaJob } from "../../src/strava/worker";
import { harness, mutation, planned, uuid } from "./helpers";

const env = readEnv({
  ...process.env,
  STRAVA_CLIENT_ID: "123",
  STRAVA_CLIENT_SECRET: "private-secret",
  STRAVA_WEBHOOK_SECRET: "test-strava-webhook-path-secret-32-characters",
  STRAVA_WEBHOOK_VERIFY_TOKEN: "verify-token",
  STRAVA_WEBHOOK_SUBSCRIPTION_ID: "77",
});
const allScopes = "read,profile:read_all,activity:read_all,activity:write";
let publishCalls = 0,
  refreshCalls = 0,
  revokeCalls = 0;
let publicationError: StravaError | null = null;
let refreshError: StravaError | null = null;
let nextRemote = 1000;
const activity = (id = "501", distance = 5000, duration = 1500) =>
  Activity.parse({
    id,
    sport_type: "Run",
    start_date: new Date(Date.now() - 86400_000).toISOString(),
    distance,
    moving_time: duration,
    elapsed_time: duration + 60,
  });
let pages: (page: number) => ReturnType<typeof Activity.parse>[];
let detail: StravaProvider["detail"];
let duringPublish: (() => Promise<void>) | undefined;
let duringRefresh: (() => Promise<void>) | undefined;
let revokedTokens: string[] = [];
const provider: StravaProvider = {
  available: true,
  exchange: async (code) => ({
    access_token: "private-access",
    refresh_token: "private-refresh",
    expires_at: Math.floor(Date.now() / 1000) + 21600,
    athlete: { id: code },
  }),
  refresh: async () => {
    refreshCalls++;
    await duringRefresh?.();
    if (refreshError) throw refreshError;
    return {
      access_token: "rotated-access",
      refresh_token: "rotated-refresh",
      expires_at: Math.floor(Date.now() / 1000) + 21600,
    };
  },
  revoke: async (token) => {
    revokeCalls++;
    revokedTokens.push(token);
  },
  zones: async () => ({
    heart_rate: {
      custom_zones: true,
      zones: [
        { min: 0, max: 120 },
        { min: 120, max: 150 },
        { min: 150, max: -1 },
      ],
    },
  }),
  activities: async (_token, _after, _before, page) => pages(page),
  detail: async (token, id) => detail(token, id),
  publish: async () => {
    publishCalls++;
    await duringPublish?.();
    if (publicationError) throw publicationError;
    return "90001";
  },
};
const h = harness({ env, strava: provider }),
  sql = h.database.client;
type Account = Awaited<ReturnType<typeof h.account>>;
const accounts: Account[] = [];
const account = async () => {
  const a = await h.account();
  accounts.push(a);
  return a;
};
beforeEach(async () => {
  publishCalls = 0;
  refreshCalls = 0;
  revokeCalls = 0;
  publicationError = null;
  refreshError = null;
  duringPublish = undefined;
  duringRefresh = undefined;
  revokedTokens = [];
  pages = () => [activity()];
  detail = async (_token, id) => ({
    ...activity(id),
    best_efforts: [{ name: "5k", distance: 5000, elapsed_time: 1480 }],
  });
  await sql`delete from strava_budget`;
});
afterEach(async () => {
  for (const a of accounts.splice(0)) {
    await sql`delete from auth_user where id=${a.userId}`;
    await sql`delete from strava_revocations where owner=${a.athleteId}`;
  }
});
afterAll(() => h.close());
const status = async (a: Account) =>
  (await a.send("/v1/integrations/strava")).json();
async function connect(
  a: Account,
  scopes = allScopes,
  keepHistory = false,
  remote = String(nextRemote++),
) {
  const response = await a.send("/v1/integrations/strava/connect", {
    autoPublish: true,
  });
  expect(response.status).toBe(200);
  const pending = await response.json();
  const completed = await a.send("/v1/integrations/strava/complete", {
    state: pending.state,
    code: remote,
    scope: scopes,
  });
  expect(completed.status).toBe(200);
  if (!keepHistory)
    await sql`update strava_jobs set state='cancelled',payload=null where athlete_id=${a.athleteId} and kind='history'`;
  return pending;
}
async function tick() {
  await sql`update strava_jobs set available_at=now() where state in ('queued','retry')`;
  return processStravaJob(sql, env, provider);
}
const workout = (overrides: Record<string, unknown> = {}) => ({
  discipline: "running",
  trainingDate: "2026-09-20",
  timezone: "America/Monterrey",
  startedAt: "2026-09-20T12:00:00Z",
  durationS: 1800,
  completionStatus: "completed",
  sourceType: "manual",
  run: { distanceM: 5000, durationS: 1800 },
  ...overrides,
});
async function save(
  a: Account,
  payload: Record<string, unknown> = workout(),
  id = uuid(),
) {
  const m = mutation("workout_result", payload, id);
  expect((await a.push(m)).results[0].status).toBe("applied");
  return { id, m };
}
const publication = async (a: Account) =>
  (
    await sql`select * from strava_jobs where athlete_id=${a.athleteId} and kind='publish'`
  )[0];
const event = (a: Record<string, unknown> = {}) => ({
  owner_id: "1000",
  object_id: "501",
  object_type: "activity",
  aspect_type: "update",
  event_time: Math.floor(Date.now() / 1000) + 1,
  subscription_id: "77",
  updates: {},
  ...a,
});
const webhook = (body: unknown, path = env.STRAVA_WEBHOOK_SECRET) =>
  h.app.request(`/webhooks/strava/${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

test("Strava routes require authentication and disabled integration remains explicit", async () => {
  expect((await h.app.request("/v1/integrations/strava")).status).toBe(401);
  const a = await account();
  expect(await status(a)).toMatchObject({
    available: true,
    status: "not_connected",
    autoPublish: false,
    history: null,
    jobs: [],
  });
});

test("OAuth state is athlete-bound, expires, is single-use and never exposes encrypted tokens", async () => {
  const a = await account(),
    b = await account();
  const pending = await (
    await a.send("/v1/integrations/strava/connect", { autoPublish: true })
  ).json();
  const url = new URL(pending.authorizationUrl);
  expect(url.searchParams.get("scope")).toContain("profile:read_all");
  expect(url.searchParams.get("redirect_uri")).toBe(
    `${env.BETTER_AUTH_URL}/integrations/strava/callback`,
  );
  const input = {
    state: pending.state,
    code: String(nextRemote++),
    scope: allScopes,
  };
  expect((await b.send("/v1/integrations/strava/complete", input)).status).toBe(
    400,
  );
  expect((await a.send("/v1/integrations/strava/complete", input)).status).toBe(
    200,
  );
  expect((await a.send("/v1/integrations/strava/complete", input)).status).toBe(
    400,
  );
  const [c] =
    await sql`select * from strava_connections where athlete_id=${a.athleteId}`;
  expect(String(c?.tokens)).not.toContain("private-access");
  expect(
    unseal(env.BETTER_AUTH_SECRET, a.athleteId, String(c?.tokens))
      .refresh_token,
  ).toBe("private-refresh");
  expect(JSON.stringify(await status(a))).not.toContain("private-");
  expect((await status(b)).jobs).toEqual([]);
  const expired = await (
    await b.send("/v1/integrations/strava/connect", {})
  ).json();
  await sql`update strava_oauth_states set expires_at=now()-interval '1 second' where athlete_id=${b.athleteId}`;
  expect(
    (
      await b.send("/v1/integrations/strava/complete", {
        ...input,
        state: expired.state,
      })
    ).status,
  ).toBe(400);
});

test("callback returns status only, cancellation clears state and one Strava identity has one local owner", async () => {
  const a = await account(),
    b = await account(),
    remote = String(nextRemote++);
  await connect(a, allScopes, false, remote);
  const p = await (await b.send("/v1/integrations/strava/connect", {})).json();
  expect(
    (
      await b.send("/v1/integrations/strava/complete", {
        state: p.state,
        code: remote,
        scope: allScopes,
      })
    ).status,
  ).toBe(409);
  const c = await (await b.send("/v1/integrations/strava/connect", {})).json();
  const response = await h.app.request(
    `/integrations/strava/callback?state=${c.state}&error=access_denied`,
  );
  expect(response.status).toBe(302);
  expect(response.headers.get("location")).toBe(
    "hybrd://integrations/strava?status=cancelled",
  );
  expect(response.headers.get("referrer-policy")).toBe("no-referrer");
  expect(
    await sql`select digest from strava_oauth_states where athlete_id=${b.athleteId}`,
  ).toHaveLength(0);
});

test("partial scopes disable publishing and preserve useful history without inventing HR zones", async () => {
  const a = await account();
  await connect(a, "activity:read", true);
  expect((await status(a)).autoPublish).toBe(false);
  expect(
    (await a.send("/v1/integrations/strava", { autoPublish: true }, "PATCH"))
      .status,
  ).toBe(409);
  for (let i = 0; i < 4; i++) await tick();
  expect((await status(a)).history).toMatchObject({
    heartRateZones: null,
    requiresReview: true,
  });
  expect((await status(a)).history.missing).toContain("heart_rate_zones");
});

test("onboarding history paginates, deduplicates, limits to a year and exposes sampled best efforts", async () => {
  const a = await account();
  pages = (page) =>
    page === 1
      ? Array.from({ length: 200 }, (_, i) =>
          activity(String(i + 1), 5000, 1500 + i),
        )
      : [
          activity("1"),
          { ...activity("300"), flagged: true },
          {
            ...activity("301"),
            start_date: new Date(Date.now() - 400 * 86400_000).toISOString(),
          },
          activity("302", 10000, 3600),
        ];
  await connect(a, allScopes, true);
  const j1 = await (await a.send("/v1/integrations/strava/history", {})).json(),
    j2 = await (await a.send("/v1/integrations/strava/history", {})).json();
  expect(j1.jobId).toBe(j2.jobId);
  for (let i = 0; i < 24; i++) await tick();
  const s = await status(a),
    p = s.history;
  expect(p.activityCount).toBe(201);
  expect(p.historyComplete).toBe(true);
  expect(p.running[2].distanceM).toBe(1010000);
  expect(p.heartRateZones.ranges[2]).toEqual({ minBpm: 150, maxBpm: null });
  expect(p.observedBestEfforts[0]).toMatchObject({
    distanceM: 5000,
    elapsedSeconds: 1480,
  });
  expect(p.bestEffortCoverage.allTimePersonalBests).toBe(false);
  expect(p.bestEffortCoverage.inspectedRuns).toBeLessThanOrEqual(18);
  expect(s.jobs.find((j: { id: string }) => j.id === j1.jobId).state).toBe(
    "completed",
  );
  expect(
    (
      await a.push(
        mutation("baseline_snapshot", {
          periodStart: p.periodStart.slice(0, 10),
          periodEnd: p.periodEnd.slice(0, 10),
          schemaVersion: 1,
          metrics: { weeklyDistanceM: p.running[1].averageWeeklyDistanceM },
          confidence: { reviewed: true },
          source: "strava",
          confirmedAt: new Date().toISOString(),
        }),
      )
    ).results[0].status,
  ).toBe("applied");
});

test("sync commits one export atomically and replay, HealthKit and skipped work cannot duplicate it", async () => {
  const a = await account();
  await connect(a);
  const { m } = await save(a);
  expect((await a.push(m)).results[0].status).toBe("applied");
  await save(a, workout({ sourceType: "healthkit" }));
  await save(a, workout({ completionStatus: "skipped", run: null }));
  const bad = mutation("workout_result", workout({ plannedWorkoutId: uuid() }));
  expect((await a.push(bad)).results[0].status).toBe("rejected");
  expect(
    await sql`select id from strava_jobs where athlete_id=${a.athleteId} and kind='publish'`,
  ).toHaveLength(1);
  await tick();
  await tick();
  expect(publishCalls).toBe(1);
  expect(await publication(a)).toMatchObject({
    state: "published",
    remote_id: "90001",
  });
});

test("missing export timing waits for correction and logical result revisions share a single publish", async () => {
  const a = await account();
  await connect(a);
  const plan = await planned(a);
  const logical = plan.run.logicalWorkoutId,
    id = uuid();
  await save(
    a,
    workout({
      plannedWorkoutId: plan.run.id,
      logicalWorkoutId: logical,
      startedAt: null,
    }),
    id,
  );
  await tick();
  expect((await publication(a))?.state).toBe("needs_details");
  expect(publishCalls).toBe(0);
  expect(
    (
      await a.push(
        mutation(
          "workout_result",
          workout({ plannedWorkoutId: plan.run.id, logicalWorkoutId: logical }),
          id,
          "update",
          "1",
        ),
      )
    ).results[0].status,
  ).toBe("applied");
  await tick();
  await save(
    a,
    workout({ plannedWorkoutId: plan.run.id, logicalWorkoutId: logical }),
  );
  await tick();
  expect(publishCalls).toBe(1);
  expect(
    await sql`select id from strava_jobs where athlete_id=${a.athleteId} and kind='publish'`,
  ).toHaveLength(1);
});

test("expired tokens rotate once, and unrecoverable authentication asks the user to reconnect", async () => {
  const a = await account();
  await connect(a);
  await save(a);
  await sql`update strava_connections set expires_at=now()-interval '1 second' where athlete_id=${a.athleteId}`;
  await tick();
  expect(refreshCalls).toBe(1);
  expect(publishCalls).toBe(1);
  const [c] =
    await sql`select tokens from strava_connections where athlete_id=${a.athleteId}`;
  expect(
    unseal(env.BETTER_AUTH_SECRET, a.athleteId, String(c?.tokens))
      .refresh_token,
  ).toBe("rotated-refresh");
  await save(a);
  refreshError = new StravaError("STRAVA_REAUTHENTICATION_REQUIRED");
  await sql`update strava_connections set expires_at=now()-interval '1 second' where athlete_id=${a.athleteId}`;
  await tick();
  expect((await status(a)).status).toBe("reauthentication_required");
  expect(publishCalls).toBe(1);
});

test("ambiguous delivery and process crashes never retry creation; owner can reconcile a verified reference", async () => {
  const a = await account(),
    b = await account();
  await connect(a);
  const { id } = await save(a);
  publicationError = new StravaError("STRAVA_NETWORK_ERROR", 60, true);
  await tick();
  const j = await publication(a);
  expect(j?.state).toBe("needs_review");
  expect(
    (await a.send(`/v1/integrations/strava/jobs/${j?.id}/retry`, {})).status,
  ).toBe(409);
  expect(
    (
      await b.send(`/v1/integrations/strava/jobs/${j?.id}/reconcile`, {
        remoteActivityId: "90001",
      })
    ).status,
  ).toBe(409);
  expect(
    (
      await a.send(`/v1/integrations/strava/jobs/${j?.id}/reconcile`, {
        remoteActivityId: "90001",
      })
    ).status,
  ).toBe(202);
  detail = async (_token, remote) => ({
    ...activity(remote),
    description: "wrong workout",
    best_efforts: [],
  });
  await tick();
  expect((await publication(a))?.state).toBe("needs_review");
  expect(
    (
      await a.send(`/v1/integrations/strava/jobs/${j?.id}/reconcile`, {
        remoteActivityId: "90001",
      })
    ).status,
  ).toBe(202);
  detail = async (_token, remote) => ({
    ...activity(remote),
    description: `Recorded with hybrd. Reference: hybrd:${id}`,
    best_efforts: [],
  });
  await tick();
  expect((await publication(a))?.state).toBe("published");
  expect(publishCalls).toBe(1);
  const second = await save(a);
  await sql`update strava_jobs set state='publishing' where workout_id=${second.id}`;
  await tick();
  expect(
    (await sql`select state from strava_jobs where workout_id=${second.id}`)[0]
      ?.state,
  ).toBe("needs_review");
  expect(publishCalls).toBe(1);
});

test("rate limits postpone safe requests and multiple workers cannot publish the same job", async () => {
  const a = await account();
  await connect(a);
  await save(a);
  publicationError = new StravaError("STRAVA_RATE_LIMITED", 120);
  await tick();
  expect((await publication(a))?.state).toBe("retry");
  await tick();
  expect(publishCalls).toBe(1);
  await sql`update strava_budget set blocked_until=null`;
  publicationError = null;
  await sql`update strava_jobs set available_at=now() where athlete_id=${a.athleteId}`;
  duringPublish = async () => {
    await Bun.sleep(20);
  };
  await Promise.all([
    processStravaJob(sql, env, provider),
    processStravaJob(sql, env, provider),
  ]);
  expect(publishCalls).toBe(2);
  expect((await publication(a))?.state).toBe("published");
});

test("turning publishing off cancels queued work and enabling it never backfills old workouts", async () => {
  const a = await account();
  await connect(a);
  await save(a);
  expect(
    (await a.send("/v1/integrations/strava", { autoPublish: false }, "PATCH"))
      .status,
  ).toBe(204);
  await save(a);
  await tick();
  expect(publishCalls).toBe(0);
  expect(
    (await a.send("/v1/integrations/strava", { autoPublish: true }, "PATCH"))
      .status,
  ).toBe(204);
  await tick();
  expect(publishCalls).toBe(0);
  await save(a);
  await tick();
  expect(publishCalls).toBe(1);
});

test("webhook authentication, deduplication, cache invalidation and deauthorization are durable", async () => {
  const a = await account(),
    remote = String(nextRemote++);
  await connect(a, allScopes, true, remote);
  for (let i = 0; i < 4; i++) await tick();
  expect((await status(a)).history).not.toBeNull();
  const challenge = await h.app.request(
    `/webhooks/strava/${env.STRAVA_WEBHOOK_SECRET}?hub.mode=subscribe&hub.verify_token=verify-token&hub.challenge=hello`,
  );
  expect(await challenge.json()).toEqual({ "hub.challenge": "hello" });
  const e = event({ owner_id: remote, aspect_type: "delete" });
  expect((await webhook(e, "wrong")).status).toBe(404);
  expect((await webhook({ ...e, subscription_id: "wrong" })).status).toBe(400);
  expect((await webhook({ ...e, subscription_id: "99" })).status).toBe(404);
  expect((await webhook(e)).status).toBe(200);
  expect((await status(a)).history).toBeNull();
  const first =
    await sql`select id from strava_jobs where athlete_id=${a.athleteId} and state='queued'`;
  await webhook(e);
  const duplicate =
    await sql`select id from strava_jobs where athlete_id=${a.athleteId} and state='queued'`;
  expect(duplicate.map((r) => String(r.id))).toEqual(
    first.map((r) => String(r.id)),
  );
  await webhook(
    event({
      owner_id: remote,
      object_type: "athlete",
      object_id: remote,
      updates: { authorized: "false" },
    }),
  );
  expect(await status(a)).toMatchObject({
    status: "disconnected",
    history: null,
    autoPublish: false,
  });
  expect(
    (
      await sql`select tokens from strava_connections where athlete_id=${a.athleteId}`
    )[0]?.tokens,
  ).toBeNull();
});

test("disconnect purges previews, is idempotent, and revokes without provider calls on the request", async () => {
  const a = await account();
  await connect(a, allScopes, true);
  await save(a);
  expect(
    (await a.send("/v1/integrations/strava", undefined, "DELETE")).status,
  ).toBe(202);
  await a.send("/v1/integrations/strava", undefined, "DELETE");
  expect(revokeCalls).toBe(0);
  expect((await a.send("/v1/integrations/strava/connect", {})).status).toBe(
    409,
  );
  expect(
    await sql`select id from strava_jobs where athlete_id=${a.athleteId} and kind='revoke'`,
  ).toHaveLength(1);
  await tick();
  expect(revokeCalls).toBe(1);
  expect(publishCalls).toBe(0);
  expect((await status(a)).status).toBe("disconnected");
});

test("account deletion removes private integration data and durably revokes its remaining grant", async () => {
  const a = await account();
  await connect(a, allScopes, true);
  expect((await a.send("/v1/account", undefined, "DELETE")).status).toBe(204);
  expect(
    await sql`select athlete_id from strava_connections where athlete_id=${a.athleteId}`,
  ).toHaveLength(0);
  expect(
    await sql`select id from strava_jobs where athlete_id=${a.athleteId}`,
  ).toHaveLength(0);
  expect(
    await sql`select owner from strava_revocations where owner=${a.athleteId}`,
  ).toHaveLength(1);
  await tick();
  expect(revokeCalls).toBe(1);
  expect(
    await sql`select owner from strava_revocations where owner=${a.athleteId}`,
  ).toHaveLength(0);
});

test("in-flight publication cannot resurrect account data after account deletion", async () => {
  const a = await account();
  await connect(a);
  await save(a);
  duringPublish = async () => {
    expect((await a.send("/v1/account", undefined, "DELETE")).status).toBe(204);
  };
  await tick();
  expect(
    await sql`select id from strava_jobs where athlete_id=${a.athleteId}`,
  ).toHaveLength(0);
  await tick();
  expect(revokeCalls).toBe(1);
});

test("new logical corrections replace an unsent result and a later skipped head cancels it", async () => {
  const a = await account();
  await connect(a);
  const p = await planned(a);
  const payload = workout({
    plannedWorkoutId: p.run.id,
    logicalWorkoutId: p.run.logicalWorkoutId,
  });
  await save(a, payload);
  const corrected = await save(a, payload);
  expect((await publication(a))?.workout_id).toBe(corrected.id);
  await save(a, { ...payload, completionStatus: "skipped", run: null });
  await tick();
  expect(publishCalls).toBe(0);
  expect((await publication(a))?.state).toBe("cancelled");
});

test("history bounded at 2,000 activities reports incompleteness and expired previews are hidden", async () => {
  const a = await account();
  pages = (page) =>
    Array.from({ length: 200 }, (_, i) => ({
      ...activity(String(page * 1000 + i)),
      sport_type: "Ride",
    }));
  await connect(a, allScopes, true);
  for (let i = 0; i < 12; i++) await tick();
  expect((await status(a)).history).toMatchObject({
    activityCount: 2000,
    historyComplete: false,
    observedBestEfforts: [],
  });
  await sql`update strava_connections set history_expires_at=now()-interval '1 second' where athlete_id=${a.athleteId}`;
  expect((await status(a)).history).toBeNull();
  await tick();
  expect(
    (
      await sql`select history from strava_connections where athlete_id=${a.athleteId}`
    )[0]?.history,
  ).toBeNull();
});

test("webhook invalidation during import prevents the previous job from restoring its preview", async () => {
  const a = await account(),
    remote = String(nextRemote++);
  await connect(a, allScopes, true, remote);
  await tick();
  await tick();
  const [prior] =
    await sql`select id from strava_jobs where athlete_id=${a.athleteId} and kind='history'`;
  detail = async (_token, id) => {
    expect(
      (await webhook(event({ owner_id: remote, aspect_type: "delete" })))
        .status,
    ).toBe(200);
    return { ...activity(id), best_efforts: [] };
  };
  await tick();
  expect((await status(a)).history).toBeNull();
  expect(
    (await sql`select state from strava_jobs where id=${String(prior?.id)}`)[0]
      ?.state,
  ).toBe("cancelled");
});

test("disconnect or account deletion during token refresh revokes the rotated token", async () => {
  for (const removeAccount of [false, true]) {
    const a = await account();
    await connect(a);
    await save(a);
    await sql`update strava_connections set expires_at=now()-interval '1 second' where athlete_id=${a.athleteId}`;
    duringRefresh = async () => {
      const response = await a.send(
        removeAccount ? "/v1/account" : "/v1/integrations/strava",
        undefined,
        "DELETE",
      );
      expect(response.status).toBe(removeAccount ? 204 : 202);
    };
    await tick();
    duringRefresh = undefined;
    await tick();
    expect(revokedTokens.at(-1)).toBe("rotated-refresh");
    expect(publishCalls).toBe(0);
  }
});
