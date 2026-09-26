import { afterAll, expect, test } from "bun:test";
import { catalogId, catalogVersion } from "../../src/catalog/data";
import { Draft, OnboardingState, Receipt } from "../../src/onboarding/schemas";
import { OnboardingPreviewSchema } from "../../src/strava/schemas";
import { harness, mutation, policyId, profile, uuid } from "./helpers";

const h = harness(),
  sql = h.database.client;
afterAll(() => h.close());
type Account = Awaited<ReturnType<typeof h.account>>;
const draft = () =>
  Draft.parse({
    schemaVersion: 1,
    profile: { ...profile, cloudAiConsent: false },
    details: {
      preferredName: "Sam",
      heightUnit: "ft_in",
      dateOfBirth: null,
      age: { years: 35, asOf: "2026-09-01" },
      weightKg: 72.543,
      heightCm: 177.8,
      heartRateZones: {
        schemaVersion: 1,
        configuration: "system",
        ranges: [
          { minBpm: 0, maxBpm: 120.5 },
          { minBpm: 120.5, maxBpm: 140.5 },
          { minBpm: 140.5, maxBpm: 160.5 },
          { minBpm: 160.5, maxBpm: 180.5 },
          { minBpm: 180.5, maxBpm: null },
        ],
      },
      runningRecords: [],
      strengthRecords: [],
    },
    runningGoal: "5k",
    strengthGoal: "strength",
    raceDate: null,
    priority: "run_first",
    runningLevel: "new",
    strengthLevel: "advanced",
    weeklyDistanceM: 70000,
    currentStrengthSessionsPerWeek: 2.5,
    baselinePeriod: { start: "2026-08-24", end: "2026-09-21" },
    availableDays: [1, 2, 3, 4, 5, 6, 7],
    desiredStrengthSessionsPerWeek: 3,
    sessionMinutes: 45,
    equipmentIds: [catalogId(1, 0), catalogId(1, 20)],
    equipmentConfirmed: true,
    focusMuscleIds: [catalogId(2, 2)],
    readiness: "returning",
    context: "Preparing for a new routine",
    wantsHealth: true,
    wantsStrava: false,
    membership: "annual",
    importDecisions: [],
  });
const call = (
  a: Account,
  path: string,
  body: unknown,
  key = uuid(),
  method = "POST",
) =>
  h.app.request(path, {
    method,
    headers: { ...a.headers, "idempotency-key": key },
    body: JSON.stringify(body),
  });
const save = (
  a: Account,
  d = draft(),
  baseRevision: string | null = null,
  key = uuid(),
) =>
  call(
    a,
    "/v1/onboarding/draft",
    { baseRevision, step: "review", draft: d },
    key,
    "PUT",
  );
const complete = (a: Account, key = uuid(), revision = "1", overrides = {}) =>
  call(
    a,
    "/v1/onboarding/complete",
    {
      draftRevision: revision,
      deviceId: a.deviceId,
      catalogVersion,
      policyVersionId: policyId,
      ...overrides,
    },
    key,
  );
const state = async (a: Account) =>
  OnboardingState.parse(await (await a.send("/v1/onboarding")).json());
const health = (
  field: "weightKg" | "weeklyDistanceM" | "currentStrengthSessionsPerWeek",
) => ({
  field,
  source: "healthkit" as const,
  decision: "accept" as const,
  batchId: uuid(),
  sourceIds: [uuid()],
  observation: {
    measuredAt: field === "weightKg" ? "2026-09-20T12:00:00Z" : null,
    fetchedAt: "2026-09-21T12:00:00Z",
    window:
      field === "weightKg"
        ? null
        : {
            start: "2026-08-24T00:00:00Z",
            end: "2026-09-21T00:00:00Z",
            timezone: "UTC",
          },
    coverage: "complete_returned_records" as const,
    durationBasis: field === "weightKg" ? null : ("active" as const),
    calculationVersion: 1 as const,
  },
});
async function preview(a: Account) {
  const p = OnboardingPreviewSchema.parse({
    id: uuid(),
    revision: "2",
    generatedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 86400_000).toISOString(),
    profile: {
      state: "ready",
      reason: null,
      data: { preferredName: "Imported Sam", weightKg: 75, measuredAt: null },
      source: "strava",
      fetchedAt: new Date().toISOString(),
      retryAfterSeconds: null,
      coverage: "unknown",
    },
    heartRateZones: {
      state: "unavailable",
      reason: "not_provided",
      data: null,
      source: "strava",
      fetchedAt: null,
      retryAfterSeconds: null,
      coverage: "unknown",
    },
    runningHistory: {
      state: "unavailable",
      reason: "scope_missing",
      data: null,
      source: "strava",
      fetchedAt: null,
      retryAfterSeconds: null,
      coverage: "unknown",
    },
  });
  await sql`insert into strava_connections (athlete_id,remote_id,generation,scopes,expires_at,status,auto_publish,onboarding_preview,history_expires_at) values (${a.athleteId},${String(Date.now()) + a.athleteId},${uuid()},${sql.json(["read", "profile:read_all"])},now()+interval '1 day','connected',false,${sql.json(p)},${new Date(p.expiresAt)})`;
  return p;
}

test("onboarding requires authentication and UUID idempotency keys, but no paid access", async () => {
  for (const [path, method] of [
    ["/v1/onboarding", "GET"],
    ["/v1/onboarding/draft", "PUT"],
    ["/v1/onboarding/complete", "POST"],
  ] as const)
    expect((await h.app.request(path, { method })).status).toBe(401);
  const a = await h.account();
  expect((await state(a)).status).toBe("not_started");
  expect(
    (
      await a.send(
        "/v1/onboarding/draft",
        { baseRevision: null, step: "review", draft: draft() },
        "PUT",
      )
    ).status,
  ).toBe(400);
  expect((await save(a)).status).toBe(200);
  expect((await complete(a)).status).toBe(200);
  expect(await (await a.send("/v1/billing/entitlements")).json()).toEqual({
    entitlements: [],
  });
});

test("drafts resume incomplete answers, isolate accounts, detect concurrency and bind idempotency to content", async () => {
  const a = await h.account(),
    b = await h.account(),
    d = draft(),
    key = uuid();
  d.runningGoal = null;
  d.details.preferredName = null;
  expect(await (await save(a, d, null, key)).json()).toEqual({
    draftRevision: "1",
  });
  expect(await (await save(a, d, null, key)).json()).toEqual({
    draftRevision: "1",
  });
  expect((await save(a, draft(), null, key)).status).toBe(409);
  expect((await state(a)).draft?.runningGoal).toBeNull();
  expect((await state(b)).draft).toBeNull();
  const concurrent = await Promise.all([
    save(a, draft(), "1"),
    save(a, draft(), "1"),
  ]);
  expect(concurrent.map((r) => r.status).sort()).toEqual([200, 409]);
  expect((await complete(a)).status).toBe(409);
  expect((await complete(b)).status).toBe(409);
});

test("manual completion restores every field and all seven Foundation weekdays through normal sync", async () => {
  const a = await h.account(),
    d = draft();
  await save(a, d);
  const response = await complete(a);
  expect(response.status).toBe(200);
  const receipt = Receipt.parse(await response.json());
  expect(receipt.planning.status).toBe("ready_for_local_planner");
  const installation = uuid();
  await h.services.registerDevice(a.userId, installation, {
    appVersion: "1",
    pushEnabled: false,
    pushEnvironment: "sandbox",
  });
  const pull = await (
    await a.send(`/v1/sync/pull?deviceId=${installation}&cursor=0&limit=100`)
  ).json();
  expect(
    pull.changes.find(
      (c: { entityType: string }) => c.entityType === "athlete_details",
    ).payload.details,
  ).toEqual(d.details);
  const preferences = pull.changes.find(
    (c: { entityType: string }) => c.entityType === "training_preferences",
  ).payload;
  expect(preferences.onboarding).toMatchObject({
    runningLevel: "new",
    strengthLevel: "advanced",
    desiredStrengthSessionsPerWeek: 3,
    equipmentConfirmed: true,
    focusMuscleIds: d.focusMuscleIds,
  });
  expect(preferences.runPriorityWeight).toBe(0.65);
  const weekdays = pull.changes
    .filter((c: { entityType: string }) => c.entityType === "availability_rule")
    .map((c: { payload: { dayOfWeek: number; maxSessions: number } }) => ({
      day: c.payload.dayOfWeek,
      max: c.payload.maxSessions,
    }));
  expect(weekdays).toEqual(
    [1, 2, 3, 4, 5, 6, 7].map((day) => ({ day, max: 1 })),
  );
  const exported = await (await a.send("/v1/account/export")).json();
  expect(exported.onboarding.completion.submissionId).toBe(
    receipt.submissionId,
  );
  expect(exported.data.baseline_snapshot[0].metrics).toMatchObject({
    weeklyDistanceM: 70000,
    currentStrengthSessionsPerWeek: 2.5,
  });
  expect(
    exported.data.planning_context_snapshot[0].snapshot.athleteDetailsId,
  ).toBe(a.athleteId);
  expect(exported.data.training_block).toEqual([]);
});

test("lost response and simultaneous completion produce exactly one receipt; new keys cannot reset setup", async () => {
  const a = await h.account(),
    key = uuid();
  await save(a);
  const responses = await Promise.all([complete(a, key), complete(a, key)]);
  expect(responses.map((r) => r.status)).toEqual([200, 200]);
  const first = await responses[0]?.json();
  expect(await responses[1]?.json()).toEqual(first);
  expect((await state(a)).completion).toEqual(first);
  expect((await complete(a, uuid())).status).toBe(409);
  expect((await complete(a, key, "2")).status).toBe(409);
  expect((await save(a, draft(), "1")).status).toBe(409);
  expect(
    await sql`select id from baseline_snapshots where athlete_id=${a.athleteId}`,
  ).toHaveLength(1);
});

test("Health-only setup preserves dated values, fractional zones and client-reported coverage without Strava", async () => {
  const a = await h.account(),
    d = draft();
  d.importDecisions = [
    health("weightKg"),
    health("weeklyDistanceM"),
    health("currentStrengthSessionsPerWeek"),
  ];
  expect((await save(a, d)).status).toBe(200);
  expect((await complete(a)).status).toBe(200);
  const exported = await (await a.send("/v1/account/export")).json();
  expect(exported.data.athlete_details[0].provenance[0]).toMatchObject({
    source: "healthkit",
    verification: "client_reported",
    observation: { measuredAt: "2026-09-20T12:00:00Z" },
  });
  expect(exported.data.baseline_snapshot[0]).toMatchObject({
    source: "healthkit",
    provenance: [
      { observation: { durationBasis: "active" } },
      { observation: { durationBasis: "active" } },
    ],
  });
});

test("Strava reviewed values are resolved from the owned preview, stored as draft references and preserved canonically", async () => {
  const a = await h.account(),
    p = await preview(a),
    d = draft(),
    key = uuid();
  d.details.preferredName = "Imported Sam";
  d.importDecisions = [
    {
      field: "preferredName",
      source: "strava",
      decision: "accept",
      previewId: p.id,
      previewRevision: p.revision,
    },
  ];
  expect((await save(a, d)).status).toBe(200);
  const [stored] =
    await sql`select draft from onboarding_states where athlete_id=${a.athleteId}`;
  expect(stored?.draft.details.preferredName).toBeNull();
  expect((await state(a)).draft?.details.preferredName).toBe("Imported Sam");
  const first = await complete(a, key);
  expect(first.status).toBe(200);
  const receipt = await first.json();
  await sql`update strava_connections set onboarding_preview=null,status='disconnected' where athlete_id=${a.athleteId}`;
  expect(await (await complete(a, key)).json()).toEqual(receipt);
  const exported = await (await a.send("/v1/account/export")).json();
  expect(exported.data.athlete_details[0].provenance[0]).toMatchObject({
    source: "strava",
    verification: "server_preview",
    editedFromSource: false,
  });
});

test("both sources can supply separate fields; explicit edited imports never get replaced by late results", async () => {
  const a = await h.account(),
    p = await preview(a),
    d = draft();
  d.importDecisions = [
    health("weightKg"),
    {
      field: "preferredName",
      source: "strava",
      decision: "edit",
      previewId: p.id,
      previewRevision: p.revision,
    },
  ];
  expect((await save(a, d)).status).toBe(200);
  expect((await state(a)).draft?.details.preferredName).toBe("Sam");
  expect((await complete(a)).status).toBe(200);
  const exported = await (await a.send("/v1/account/export")).json();
  expect(exported.data.athlete_details[0].provenance[1].editedFromSource).toBe(
    true,
  );
});

test("forged, cross-account, refreshed and expired previews require review; expired data does not survive draft restore", async () => {
  const a = await h.account(),
    b = await h.account(),
    p = await preview(a),
    d = draft();
  d.importDecisions = [
    {
      field: "preferredName",
      source: "strava",
      decision: "accept",
      previewId: p.id,
      previewRevision: p.revision,
    },
  ];
  expect((await save(b, d)).status).toBe(409);
  expect((await save(a, d)).status).toBe(409);
  d.details.preferredName = "Imported Sam";
  expect((await save(a, d)).status).toBe(200);
  await sql`update strava_connections set onboarding_preview=jsonb_set(onboarding_preview,'{revision}','"3"'::jsonb) where athlete_id=${a.athleteId}`;
  expect((await complete(a)).status).toBe(409);
  expect((await state(a)).reviewIssues[0]?.code).toBe("IMPORT_REVIEW_REQUIRED");
  await sql`update strava_connections set history_expires_at=now()-interval '1 second' where athlete_id=${a.athleteId}`;
  const expired = await state(a);
  expect(expired.reviewIssues[0]?.code).toBe("IMPORT_PREVIEW_EXPIRED");
  expect(expired.draft?.details.preferredName).toBeNull();
  expect(
    await sql`select id from athlete_details where athlete_id=${a.athleteId}`,
  ).toHaveLength(0);
});

test("zero and high volume are saved without clamping, with an actionable planner capability state", async () => {
  for (const meters of [0, 70123.456789, 250000]) {
    const a = await h.account(),
      d = draft();
    d.weeklyDistanceM = meters;
    d.currentStrengthSessionsPerWeek = 0;
    d.equipmentIds = [];
    await save(a, d);
    const r = await complete(a);
    expect(r.status).toBe(200);
    expect((await r.json()).planning.status).toBe(
      meters === 70123.456789
        ? "ready_for_local_planner"
        : "unsupported_baseline",
    );
    const [b] =
      await sql`select metrics from baseline_snapshots where athlete_id=${a.athleteId}`;
    expect(b?.metrics.weeklyDistanceM).toBe(meters);
  }
});

test("invalid mapping, policy, device and incomplete review cannot leave canonical partial data", async () => {
  const a = await h.account(),
    d = draft();
  d.equipmentIds = [uuid()];
  await save(a, d);
  for (const overrides of [
    {},
    { catalogVersion: 999 },
    { deviceId: uuid() },
    { policyVersionId: uuid() },
  ])
    expect(
      (await complete(a, uuid(), "1", overrides)).status,
    ).toBeGreaterThanOrEqual(400);
  expect(
    await sql`select id from athlete_details where athlete_id=${a.athleteId}`,
  ).toHaveLength(0);
  const missing = draft();
  missing.weeklyDistanceM = null;
  await save(a, missing, "1");
  const r = await complete(a, uuid(), "2");
  expect(r.status).toBe(422);
  expect((await r.json()).error.details.fields).toContain("weeklyDistanceM");
});

test("an injected failure after canonical writes rolls back profile, aggregates, sync events and receipt", async () => {
  const a = await h.account();
  await save(a);
  const [before] =
    await sql`select count(*)::int n from sync_change_log where athlete_id=${a.athleteId}`;
  await sql.unsafe(
    `create function onboarding_test_failure() returns trigger language plpgsql as $$ begin if NEW.athlete_id='${a.athleteId}'::uuid then raise exception 'injected onboarding failure'; end if; return NEW; end $$`,
  );
  await sql`create trigger onboarding_test_failure before insert on planning_context_snapshots for each row execute function onboarding_test_failure()`;
  try {
    expect((await complete(a)).status).toBe(500);
  } finally {
    await sql`drop trigger onboarding_test_failure on planning_context_snapshots`;
    await sql`drop function onboarding_test_failure()`;
  }
  expect(
    await sql`select id from baseline_snapshots where athlete_id=${a.athleteId}`,
  ).toHaveLength(0);
  expect(
    await sql`select id from athlete_details where athlete_id=${a.athleteId}`,
  ).toHaveLength(0);
  expect((await state(a)).status).toBe("draft");
  expect(
    (
      await sql`select count(*)::int n from sync_change_log where athlete_id=${a.athleteId}`
    )[0]?.n,
  ).toBe(before?.n);
  expect(
    (await sql`select revision::text from athletes where id=${a.athleteId}`)[0]
      ?.revision,
  ).toBe("1");
  expect((await complete(a)).status).toBe(200);
});

test("existing setup and profile edits on another device are protected from repeat onboarding", async () => {
  const a = await h.account();
  await save(a);
  await a.push(mutation("athlete", profile, a.athleteId, "update", "1"));
  expect((await complete(a)).status).toBe(409);
  await save(a, draft(), "1");
  await a.push(
    mutation("athlete_goal", {
      discipline: "running",
      goalType: "general_fitness",
      status: "active",
    }),
  );
  expect((await complete(a, uuid(), "2")).status).toBe(409);
});

test("details can be explicitly edited via sync; provenance cannot be forged and account deletion cascades", async () => {
  const a = await h.account(),
    d = draft();
  d.importDecisions = [health("weightKg")];
  await save(a, d);
  await complete(a);
  const changed = { ...d.details, weightKg: 80 };
  const r = await a.push(
    mutation(
      "athlete_details",
      { schemaVersion: 1, details: changed },
      a.athleteId,
      "update",
      "1",
    ),
  );
  expect(r.results[0].status).toBe("applied");
  expect(
    (
      await sql`select provenance from athlete_details where id=${a.athleteId}`
    )[0]?.provenance,
  ).toEqual([]);
  expect((await a.send("/v1/account", undefined, "DELETE")).status).toBe(204);
  for (const table of [
    "onboarding_states",
    "onboarding_requests",
    "athlete_details",
  ])
    expect(
      await sql`select athlete_id from ${sql(table)} where athlete_id=${a.athleteId}`,
    ).toHaveLength(0);
});
