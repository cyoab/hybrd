import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { eq, inArray } from "drizzle-orm";
import { createApp } from "../../src/api/app";
import { createServices } from "../../src/api/services";
import { createAuth } from "../../src/auth";
import { readEnv } from "../../src/config/env";
import { createDatabase } from "../../src/db/client";
import { athletes, deviceInstallations, user } from "../../src/db/schema";

const env = readEnv();
if (
  env.NODE_ENV !== "test" ||
  !new URL(env.DATABASE_URL).pathname.endsWith("_test")
) {
  throw new Error(
    "Integration tests require NODE_ENV=test and a database name ending in _test. Use make test.",
  );
}
const database = createDatabase(env.DATABASE_URL);
const auth = createAuth(env, database.db);
const app = createApp(createServices(database, auth), { logging: false });
const accounts: { userId: string; token: string; athleteId: string }[] = [];
const deviceId = crypto.randomUUID();

async function signUp() {
  const response = await app.request("/api/auth/sign-up/email", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin: env.BETTER_AUTH_URL,
    },
    body: JSON.stringify({
      name: "Integration Athlete",
      email: `${crypto.randomUUID()}@example.test`,
      password: "integration-only-password-2026",
    }),
  });
  expect(response.status).toBe(200);
  const body = await response.json();
  expect(typeof body.token).toBe("string");
  const [athlete] = await database.db
    .select()
    .from(athletes)
    .where(eq(athletes.authUserId, body.user.id));
  expect(athlete).toBeDefined();
  if (!athlete) throw new Error("Auth did not provision an athlete.");
  return {
    userId: body.user.id as string,
    token: body.token as string,
    athleteId: athlete.id,
  };
}

beforeAll(async () => {
  accounts.push(await signUp(), await signUp());
});
afterAll(async () => {
  const ids = accounts.map((account) => account.athleteId);
  if (ids.length) {
    await database.db
      .delete(deviceInstallations)
      .where(inArray(deviceInstallations.athleteId, ids));
    await database.db.delete(athletes).where(inArray(athletes.id, ids));
    await database.db.delete(user).where(
      inArray(
        user.id,
        accounts.map((account) => account.userId),
      ),
    );
  }
  await database.close();
});

function headers(accountIndex = 0) {
  const account = accounts[accountIndex];
  if (!account) throw new Error("Missing test account");
  return {
    authorization: `Bearer ${account.token}`,
    "content-type": "application/json",
  };
}

describe("PostgreSQL and Better Auth integration", () => {
  test("a real bearer session bootstraps only its own athlete", async () => {
    const response = await app.request("/v1/bootstrap", { headers: headers() });
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.athlete.id).toBe(accounts[0]?.athleteId);
    expect(body.athlete.revision).toBe("1");
    expect(body.sync.available).toBe(false);
    expect(body.entitlements).toEqual([]);
    expect(body.device.registered).toBe(false);
    expect(
      (
        await app.request("/v1/bootstrap", {
          headers: { authorization: "Bearer invented-token" },
        })
      ).status,
    ).toBe(401);
  });

  test("device registration is retry-safe and cannot be stolen by another athlete", async () => {
    const request = {
      method: "PUT",
      headers: headers(),
      body: JSON.stringify({ appVersion: "0.1.0", pushEnabled: false }),
    };
    expect((await app.request(`/v1/devices/${deviceId}`, request)).status).toBe(
      200,
    );
    expect((await app.request(`/v1/devices/${deviceId}`, request)).status).toBe(
      200,
    );
    const stolen = await app.request(`/v1/devices/${deviceId}`, {
      ...request,
      headers: headers(1),
    });
    expect(stolen.status).toBe(409);
    const own = await app.request(`/v1/bootstrap?deviceId=${deviceId}`, {
      headers: headers(),
    });
    expect((await own.json()).device.registered).toBe(true);
    const other = await app.request(`/v1/bootstrap?deviceId=${deviceId}`, {
      headers: headers(1),
    });
    expect((await other.json()).device.registered).toBe(false);
  });

  test("revocation is ownership-scoped and repeatable", async () => {
    await app.request(`/v1/devices/${deviceId}`, {
      method: "DELETE",
      headers: headers(1),
    });
    let [device] = await database.db
      .select()
      .from(deviceInstallations)
      .where(eq(deviceInstallations.id, deviceId));
    expect(device?.revokedAt).toBeNull();
    for (let attempt = 0; attempt < 2; attempt++)
      expect(
        (
          await app.request(`/v1/devices/${deviceId}`, {
            method: "DELETE",
            headers: headers(),
          })
        ).status,
      ).toBe(204);
    [device] = await database.db
      .select()
      .from(deviceInstallations)
      .where(eq(deviceInstallations.id, deviceId));
    expect(device?.revokedAt).toBeInstanceOf(Date);
    expect(device?.pushToken).toBeNull();
    expect(device?.pushEnabled).toBe(false);
  });

  test("published policy is available with a reusable ETag", async () => {
    const response = await app.request("/v1/config/training-policy", {
      headers: headers(),
    });
    expect(response.status).toBe(200);
    expect((await response.json()).config.features.sync).toBe(false);
    const cached = await app.request("/v1/config/training-policy", {
      headers: {
        ...headers(),
        "if-none-match": response.headers.get("etag") ?? "",
      },
    });
    expect(cached.status).toBe(304);
  });

  test("sign-out revokes the bearer session", async () => {
    const response = await app.request("/api/auth/sign-out", {
      method: "POST",
      headers: { ...headers(), origin: env.BETTER_AUTH_URL },
      body: "{}",
    });
    expect(response.status).toBe(200);
    expect(
      (await app.request("/v1/bootstrap", { headers: headers() })).status,
    ).toBe(401);
  });
});
