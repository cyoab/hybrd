import { expect } from "bun:test";
import { createApp } from "../../src/api/app";
import { createServices } from "../../src/api/services";
import { createAuth } from "../../src/auth";
import { readEnv } from "../../src/config/env";
import { createDatabase } from "../../src/db/client";
import { SyncMutationSchema } from "../../src/sync/schemas";
export const uuid = () => crypto.randomUUID();
export function harness(options: Parameters<typeof createServices>[2] = {}) {
  const env = readEnv();
  if (
    env.NODE_ENV !== "test" ||
    !new URL(env.DATABASE_URL).pathname.endsWith("_test")
  )
    throw new Error("Use the isolated test database.");
  const database = createDatabase(env.DATABASE_URL),
    auth = createAuth(env, database.db),
    services = createServices(database, auth, options),
    app = createApp(services, { logging: false });
  const accounts: string[] = [];
  async function account() {
    const r = await app.request("/api/auth/sign-up/email", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        origin: env.BETTER_AUTH_URL,
      },
      body: JSON.stringify({
        name: "Test",
        email: `${uuid()}@example.test`,
        password: "Test-only-password-2026",
      }),
    });
    expect(r.status).toBe(200);
    const body = await r.json(),
      headers = {
        authorization: `Bearer ${body.token}`,
        "content-type": "application/json",
      };
    accounts.push(body.user.id);
    const b = await services.bootstrap(body.user.id);
    const deviceId = uuid();
    await services.registerDevice(body.user.id, deviceId, {
      appVersion: "1.0",
      pushEnabled: false,
      pushEnvironment: "sandbox",
    });
    const send = async (
      path: string,
      input?: unknown,
      method = input ? "POST" : "GET",
    ) =>
      app.request(path, {
        method,
        headers,
        body: input ? JSON.stringify(input) : undefined,
      });
    const push = async (...mutations: unknown[]) => {
      const r = await send("/v1/sync/push", { deviceId, mutations });
      expect(r.status).toBe(200);
      return r.json();
    };
    return {
      userId: body.user.id as string,
      athleteId: b.athlete.id,
      deviceId,
      headers,
      send,
      push,
    };
  }
  return {
    env,
    database,
    auth,
    services,
    app,
    account,
    close: async () => {
      for (const id of accounts)
        await database.client`delete from auth_user where id=${id}`;
      await database.close();
    },
  };
}
export function mutation(
  entityType: string,
  payload: unknown,
  entityId: string = uuid(),
  operation = "create",
  baseRevision: string | null = null,
) {
  return SyncMutationSchema.parse({
    id: uuid(),
    entityType,
    entityId,
    operation,
    baseRevision,
    payload,
  });
}
export const profile = {
  timezone: "America/Monterrey",
  locale: "en",
  distanceUnit: "km",
  loadUnit: "kg",
  weekStartsOn: 1,
  trainingDayBoundary: null,
  cloudAiConsent: true,
};
export const preferences = {
  priorityMode: "balanced",
  runPriorityWeight: 0.5,
  strengthPriorityWeight: 0.5,
  strengthObjective: "mixed",
};
export const goal = {
  discipline: "running",
  goalType: "race",
  status: "active",
  targetDate: "2026-12-01",
  targetValue: 5000,
  targetUnit: "meters",
};
export const policyId = "00000000-0000-4000-8000-000000000002";
export function contextPayload() {
  return {
    baselineSnapshotId: null,
    schemaVersion: 1,
    policyVersionId: policyId,
    snapshot: {
      goals: [],
      preferences,
      availabilityRules: [],
      availabilityOverrides: [],
      equipmentIds: [],
      recentFeatures: {},
    },
  };
}
export function runWorkout() {
  return {
    id: uuid(),
    logicalWorkoutId: uuid(),
    discipline: "running",
    workoutType: "easy",
    scheduledDate: "2026-10-02",
    timezone: "America/Monterrey",
    title: "Easy run",
    priority: "supporting",
    run: {
      primaryTargetType: "rpe",
      blocks: [
        {
          id: uuid(),
          sequence: 0,
          repeatCount: 1,
          steps: [
            {
              id: uuid(),
              sequence: 0,
              stepKind: "steady",
              durationS: 1800,
              rpeMin: 3,
              rpeMax: 4,
            },
          ],
        },
      ],
    },
  };
}
export function strengthWorkout() {
  return {
    id: uuid(),
    logicalWorkoutId: uuid(),
    discipline: "strength",
    workoutType: "full_body",
    scheduledDate: "2026-10-03",
    timezone: "America/Monterrey",
    title: "Strength",
    priority: "key",
    strength: {
      sessionFocus: "full_body",
      exercises: [
        {
          id: uuid(),
          exerciseId: "10000000-0000-4000-8003-000000000000",
          sequence: 0,
          substitutionAllowed: true,
          sets: [
            {
              id: uuid(),
              setNumber: 1,
              setKind: "working",
              repsMin: 5,
              repsMax: 5,
              loadKg: 60,
            },
          ],
          substitutions: [],
        },
      ],
    },
  };
}
export async function planned(
  a: Awaited<ReturnType<ReturnType<typeof harness>["account"]>>,
) {
  const blockId = uuid(),
    contextId = uuid(),
    planId = uuid(),
    run = runWorkout(),
    strength = strengthWorkout();
  const setup = await a.push(
    mutation(
      "training_block",
      {
        name: "Base",
        startDate: "2026-10-01",
        endDate: "2026-10-31",
        phase: "build",
        status: "draft",
      },
      blockId,
    ),
    mutation("planning_context_snapshot", contextPayload(), contextId),
  );
  expect(setup.results.map((r: { status: string }) => r.status)).toEqual([
    "applied",
    "applied",
  ]);
  const plan = {
    trainingBlockId: blockId,
    planningContextSnapshotId: contextId,
    policyVersionId: policyId,
    origin: "initial",
    workouts: [run, strength],
  };
  expect(
    (await a.push(mutation("plan_version", plan, planId))).results[0].status,
  ).toBe("applied");
  const activate = (id: string = planId, base: string | null = null) =>
    mutation(
      "plan_version",
      {
        expectedActivePlanVersionId: base,
        accepted: true,
        reasonCode: "user_acceptance",
        explanation: "Accepted initial plan",
      },
      id,
      "activate_plan",
      "1",
    );
  expect((await a.push(activate())).results[0].status).toBe("applied");
  return { blockId, contextId, planId, run, strength, plan, activate };
}
