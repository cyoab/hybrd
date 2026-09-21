import { describe, expect, test } from "bun:test";
import { createApp, openApiInfo } from "../../src/api/app";
import type { AppDependencies } from "../../src/api/dependencies";

function dependencies(
  overrides: Partial<AppDependencies> = {},
): AppDependencies {
  return {
    checkDatabase: async () => {},
    authenticate: async () => null,
    handleAuth: async () => new Response(null, { status: 404 }),
    bootstrap: async () => {
      throw new Error("Unexpected bootstrap");
    },
    trainingPolicy: async () => null,
    registerDevice: async () => {},
    revokeDevice: async () => {},
    entitlements: async () => [],
    ...overrides,
  };
}
const appWith = (overrides: Partial<AppDependencies> = {}) =>
  createApp(dependencies(overrides), { logging: false });

describe("API foundation", () => {
  test("liveness survives a DB outage, readiness returns a sanitized 503", async () => {
    const app = appWith({
      checkDatabase: async () => {
        throw new Error("postgres://secret:password@db");
      },
    });
    expect((await app.request("/health/live")).status).toBe(200);
    const response = await app.request("/health/ready");
    expect(response.status).toBe(503);
    const body = await response.json();
    expect(body.error.code).toBe("DATABASE_UNAVAILABLE");
    expect(body.error.requestId).toBe(response.headers.get("x-request-id"));
    expect(JSON.stringify(body)).not.toContain("password");
  });

  test("all domain endpoints require a valid session", async () => {
    const app = appWith();
    for (const [method, path] of [
      ["GET", "/v1/bootstrap"],
      ["GET", "/v1/config/training-policy"],
      ["GET", "/v1/sync/pull"],
      ["POST", "/v1/sync/push"],
      ["PUT", `/v1/devices/${crypto.randomUUID()}`],
      ["POST", "/v1/intelligence/decision"],
      ["POST", "/v1/intelligence/chat"],
      ["POST", "/v1/billing/apple/transactions"],
      ["GET", "/v1/billing/entitlements"],
      ["DELETE", "/v1/account"],
    ] as const)
      expect((await app.request(path, { method })).status).toBe(401);
  });

  test("authenticated placeholders never acknowledge mutations", async () => {
    const app = appWith({ authenticate: async () => "user" });
    const response = await app.request("/v1/sync/push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        deviceId: crypto.randomUUID(),
        mutations: [
          {
            id: crypto.randomUUID(),
            entityId: crypto.randomUUID(),
            entityType: "athlete_goal",
            operation: "create",
            baseRevision: null,
            payload: {},
          },
        ],
      }),
    });
    expect(response.status).toBe(501);
    expect((await response.json()).error.code).toBe("NOT_IMPLEMENTED");
    expect((await app.request("/v1/sync/pull")).status).toBe(501);
  });

  test("invalid inputs fail before the persistence service", async () => {
    let writes = 0;
    const app = appWith({
      authenticate: async () => "user",
      registerDevice: async () => {
        writes++;
      },
    });
    for (const body of [
      { appVersion: "0.1", pushEnabled: true },
      { appVersion: "0.1", athleteId: "other-user" },
    ]) {
      const response = await app.request(`/v1/devices/${crypto.randomUUID()}`, {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      });
      expect(response.status).toBe(400);
      expect((await response.json()).error.code).toBe("VALIDATION_ERROR");
    }
    expect(writes).toBe(0);
    expect((await app.request("/v1/sync/pull?cursor=-1")).status).toBe(400);
  });

  test("policy supports conditional requests and an absent-policy error", async () => {
    const app = appWith({
      authenticate: async () => "user",
      trainingPolicy: async () => ({
        version: 1,
        schemaVersion: 1,
        checksum: "sha256:abc",
        config: {},
        minimumAppVersion: null,
      }),
    });
    const initial = await app.request("/v1/config/training-policy");
    expect(initial.status).toBe(200);
    expect(initial.headers.get("etag")).toBe('"sha256:abc"');
    const cached = await app.request("/v1/config/training-policy", {
      headers: { "if-none-match": 'W/"sha256:abc"' },
    });
    expect(cached.status).toBe(304);
    expect(await cached.text()).toBe("");
    expect(
      (
        await appWith({ authenticate: async () => "user" }).request(
          "/v1/config/training-policy",
        )
      ).status,
    ).toBe(503);
  });

  test("malformed JSON and oversized requests use the error envelope", async () => {
    const app = appWith({ authenticate: async () => "user" });
    for (const [body, status] of [
      ["{", 400],
      ["x".repeat(1024 * 1024 + 1), 413],
    ] as const) {
      const response = await app.request("/v1/sync/push", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body,
      });
      expect(response.status).toBe(status);
      expect((await response.json()).error.requestId).toBeTruthy();
    }
  });

  test("unexpected errors never disclose internal exception text", async () => {
    const app = appWith({
      authenticate: async () => "user",
      bootstrap: async () => {
        throw new Error("private athlete health data");
      },
    });
    const response = await app.request("/v1/bootstrap");
    expect(response.status).toBe(500);
    expect(await response.text()).not.toContain("private athlete");
  });

  test("OpenAPI is available offline and placeholders have no success response", () => {
    const spec = appWith().getOpenAPI31Document(openApiInfo);
    expect(spec.openapi).toBe("3.1.0");
    expect(
      spec.paths?.["/v1/sync/push"]?.post?.responses?.["200"],
    ).toBeUndefined();
    expect(
      spec.paths?.["/v1/sync/push"]?.post?.responses?.["501"],
    ).toBeDefined();
  });
});
