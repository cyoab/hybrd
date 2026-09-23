import { expect, test } from "bun:test";
import { readEnv } from "../../src/config/env";
import { seal, unseal } from "../../src/strava/crypto";
import {
  bestCandidates,
  historyPreview,
  newHistory,
  summarizeActivity,
} from "../../src/strava/history";
import {
  Activity,
  StravaError,
  stravaProvider,
} from "../../src/strava/provider";
import { publishPayload } from "../../src/strava/worker";

const env = readEnv({
  DATABASE_URL: "postgres://test:test@localhost/test",
  BETTER_AUTH_URL: "https://api.example.test",
  BETTER_AUTH_SECRET: "strava-unit-test-secret-32-characters-long",
  STRAVA_CLIENT_ID: "123",
  STRAVA_CLIENT_SECRET: "private-client-secret",
});
const run = (
  id: string,
  distance = 5000,
  moving = 1500,
  date = "2026-09-20T10:00:00Z",
) =>
  Activity.parse({
    id,
    sport_type: "Run",
    start_date: date,
    distance,
    moving_time: moving,
    elapsed_time: moving + 50,
  });
const providerWith = (
  callback: (url: string, init: RequestInit) => Promise<Response>,
) =>
  stravaProvider(env, ((url: unknown, init: RequestInit) =>
    callback(String(url), init)) as typeof fetch);

test("Strava tokens are randomized, encrypted and bound to their athlete and secret", () => {
  const tokens = {
    access_token: "private-access",
    refresh_token: "private-refresh",
  };
  const a = seal(env.BETTER_AUTH_SECRET, "owner", tokens),
    b = seal(env.BETTER_AUTH_SECRET, "owner", tokens);
  expect(a).not.toBe(b);
  expect(a).not.toContain(tokens.access_token);
  expect(unseal(env.BETTER_AUTH_SECRET, "owner", a)).toEqual(tokens);
  expect(() => unseal(env.BETTER_AUTH_SECRET, "other", a)).toThrow();
  expect(() => unseal("wrong-key", "owner", a)).toThrow();
  const parts = a.split(".");
  parts[2] = Buffer.alloc(16).toString("base64url");
  expect(() =>
    unseal(env.BETTER_AUTH_SECRET, "owner", parts.join(".")),
  ).toThrow();
});

test("history reports distance-weighted pace and distinct rolling windows", () => {
  const h = newHistory(Date.parse("2026-09-23T00:00:00Z"));
  h.complete = true;
  h.activities = [
    run("1"),
    run("2", 10000, 4000),
    run("3", 1000, 500, "2026-08-30T00:00:00Z"),
    run("4", 20000, 7000, "2025-10-01T00:00:00Z"),
  ].map(summarizeActivity);
  const preview = historyPreview(h);
  expect(preview.running[0]).toMatchObject({
    runs: 2,
    distanceM: 15000,
    movingSeconds: 5500,
    averageMovingPaceSecondsPerKm: 367,
  });
  expect(preview.running[1]?.runs).toBe(3);
  expect(preview.running[2]).toMatchObject({ runs: 4, distanceM: 36000 });
  expect(preview.bestEffortCoverage.allTimePersonalBests).toBe(false);
  expect(preview.requiresReview).toBe(true);
  expect(preview.longestRunM).toBe(20000);
});

test("empty history leaves pace and longest run unknown, never invents PBs or HR zones", () => {
  const h = newHistory();
  h.zonesUnavailable = true;
  const p = historyPreview(h);
  expect(p.running.every((w) => w.averageMovingPaceSecondsPerKm === null)).toBe(
    true,
  );
  expect(p.heartRateZones).toBeNull();
  expect(p.observedBestEfforts).toEqual([]);
  expect(p.longestRunM).toBeNull();
  expect(p.missing).toContain("heart_rate_zones");
});

test("best-effort selection is bounded and excludes manual, flagged and non-run activities", () => {
  const activities = Array.from({ length: 100 }, (_, i) =>
    summarizeActivity(run(String(i + 1), 45000, 15000 + i)),
  );
  activities.push(
    summarizeActivity({ ...run("900", 50000, 100), manual: true }),
    summarizeActivity({ ...run("901", 50000, 100), flagged: true }),
    summarizeActivity({ ...run("902", 50000, 100), sport_type: "Ride" }),
  );
  const selected = bestCandidates(activities);
  expect(selected.length).toBeLessThanOrEqual(18);
  expect(selected).not.toContain("900");
  expect(selected).not.toContain("901");
  expect(selected).not.toContain("902");
});

test("workout publishing uses real duration and local wall time; incomplete records wait", () => {
  const w = {
    id: "workout",
    discipline: "running",
    started_at: "2026-09-20T12:00:00Z",
    timezone: "America/Monterrey",
    duration_s: 1800,
    distance_m: 5000,
  };
  expect(publishPayload(w)).toMatchObject({
    sport_type: "Run",
    start_date_local: "2026-09-20T06:00:00Z",
    elapsed_time: 1800,
    distance: 5000,
    description: "Recorded with hybrd. Reference: hybrd:workout",
  });
  expect(publishPayload({ ...w, started_at: null })).toBeNull();
  expect(publishPayload({ ...w, duration_s: null })).toBeNull();
  const strength = publishPayload({ ...w, discipline: "strength" });
  expect(strength?.sport_type).toBe("WeightTraining");
  expect(strength).not.toHaveProperty("distance");
});

test("Strava OAuth and revocation use encoded bodies and keep credentials off URLs", async () => {
  const requests: { url: string; init: RequestInit }[] = [];
  const p = providerWith(async (url, init) => {
    requests.push({ url, init });
    return Response.json({
      access_token: "access",
      refresh_token: "refresh",
      expires_at: 2000000000,
      athlete: { id: 123 },
    });
  });
  expect((await p.exchange("a+b&c")).athlete?.id).toBe("123");
  await p.refresh("refresh+&");
  await p.revoke("refresh-token");
  expect(new URLSearchParams(String(requests[0]?.init.body)).get("code")).toBe(
    "a+b&c",
  );
  expect(
    new URLSearchParams(String(requests[1]?.init.body)).get("grant_type"),
  ).toBe("refresh_token");
  expect(requests[2]?.url).toBe("https://www.strava.com/oauth/revoke");
  expect(
    new Headers(requests[2]?.init.headers).get("authorization"),
  ).toStartWith("Basic ");
  expect(
    requests.every((r) => !r.url.includes(env.STRAVA_CLIENT_SECRET ?? "!")),
  ).toBe(true);
});

test("publishes distinguish safe rate-limit retries from ambiguous network and server failures", async () => {
  const payload = publishPayload({
    id: "w",
    discipline: "strength",
    started_at: "2026-09-20T12:00:00Z",
    timezone: "UTC",
    duration_s: 60,
  });
  if (!payload) throw new Error("fixture");
  for (const status of [429, 500, 400]) {
    const p = providerWith(
      async () =>
        new Response("sensitive provider error", {
          status,
          headers: { "Retry-After": "120" },
        }),
    );
    try {
      await p.publish("secret", payload);
      throw new Error("expected failure");
    } catch (e) {
      expect(e).toBeInstanceOf(StravaError);
      expect((e as StravaError).ambiguous).toBe(status === 500);
      expect((e as StravaError).retryAfter).toBe(
        status === 429 ? 120 : status === 500 ? 60 : 0,
      );
      expect(String(e)).not.toContain("sensitive");
    }
  }
  await expect(
    providerWith(async () => {
      throw new Error("timeout");
    }).publish("secret", payload),
  ).rejects.toMatchObject({ ambiguous: true });
  await expect(
    providerWith(async () => Response.json({})).publish("secret", payload),
  ).rejects.toMatchObject({ ambiguous: true });
});

test("provider preserves large string IDs and rejects unsafe numeric IDs", async () => {
  expect(Activity.parse({ ...run("1"), id: "999999999999999999" }).id).toBe(
    "999999999999999999",
  );
  expect(() =>
    Activity.parse({ ...run("1"), id: Number.MAX_SAFE_INTEGER + 1 }),
  ).toThrow();
  let requested = "";
  const p = providerWith(async (url) => {
    requested = url;
    return Response.json([run("1")]);
  });
  await p.activities("token", 10, 20, 2);
  expect(requested).toEndWith("after=10&before=20&page=2&per_page=200");
});

test("optional configuration permits webhook verification before subscription ID exists", () => {
  expect(() =>
    readEnv({
      DATABASE_URL: env.DATABASE_URL,
      BETTER_AUTH_URL: env.BETTER_AUTH_URL,
      BETTER_AUTH_SECRET: env.BETTER_AUTH_SECRET,
      STRAVA_CLIENT_ID: "123",
    }),
  ).toThrow("together");
  const webhook = readEnv({
    DATABASE_URL: env.DATABASE_URL,
    BETTER_AUTH_URL: env.BETTER_AUTH_URL,
    BETTER_AUTH_SECRET: env.BETTER_AUTH_SECRET,
    STRAVA_CLIENT_ID: "123",
    STRAVA_CLIENT_SECRET: "test",
    STRAVA_WEBHOOK_SECRET: "long-random-path-secret-32-characters",
    STRAVA_WEBHOOK_VERIFY_TOKEN: "verify",
  });
  expect(webhook.STRAVA_WEBHOOK_SUBSCRIPTION_ID).toBeUndefined();
});

test("pace excludes activities missing either distance or moving time", () => {
  const h = newHistory(Date.parse("2026-09-23T00:00:00Z"));
  h.activities = [run("1"), run("2", 5000, 0), run("3", 0, 600)].map(
    summarizeActivity,
  );
  const p = historyPreview(h);
  expect(p.running[0]).toMatchObject({
    distanceM: 10000,
    movingSeconds: 2100,
    averageMovingPaceSecondsPerKm: 300,
  });
});

test("an invalid refresh grant requires reauthentication instead of retrying forever", async () => {
  const p = providerWith(
    async () => new Response("invalid grant", { status: 400 }),
  );
  await expect(p.refresh("expired")).rejects.toMatchObject({
    code: "STRAVA_REAUTHENTICATION_REQUIRED",
    retryAfter: 0,
  });
});
