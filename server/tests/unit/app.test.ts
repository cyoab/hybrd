import { describe, expect, test } from "bun:test";
import { createApp, openApiInfo } from "../../src/api/app";
import type { AppDependencies } from "../../src/api/dependencies";
import { developmentPolicy } from "../../src/config/policy";

function dependencies(
  overrides: Partial<AppDependencies> = {},
): AppDependencies {
  return {
    agent: {
      capabilities: async () => {
        throw new Error("unused");
      },
      create: async () => {
        throw new Error("unused");
      },
      get: async () => {
        throw new Error("unused");
      },
      events: async () => {
        throw new Error("unused");
      },
      cancel: async () => {
        throw new Error("unused");
      },
      memories: async () => {
        throw new Error("unused");
      },
      putMemory: async () => {
        throw new Error("unused");
      },
      forgetMemory: async () => {
        throw new Error("unused");
      },
    },
    onboarding: {
      get: async () => {
        throw new Error("unused");
      },
      save: async () => {
        throw new Error("unused");
      },
      complete: async () => {
        throw new Error("unused");
      },
    },
    strava: {
      status: async () => {
        throw new Error("Unexpected Strava");
      },
      connect: async () => {
        throw new Error("Unexpected Strava");
      },
      complete: async () => {
        throw new Error("Unexpected Strava");
      },
      refreshHistory: async () => {
        throw new Error("Unexpected Strava");
      },
      settings: async () => {},
      disconnect: async () => {},
      retry: async () => {},
      reconcile: async () => {},
      callback: async () => "",
      verifyWebhook: () => {},
      webhook: async () => {},
    },
    progress: {
      summary: async () => {
        throw new Error("Unexpected progress");
      },
      comparison: async () => {
        throw new Error("Unexpected progress");
      },
      activity: async () => {
        throw new Error("Unexpected progress");
      },
    },
    billing: {
      submit: async () => ({ entitlements: [] }),
      notification: async () => {},
    },
    intelligence: {
      decision: async () => {
        throw new Error("Unexpected decision");
      },
      chat: async () => {
        throw new Error("Unexpected chat");
      },
    },
    sync: {
      push: async () => {
        throw new Error("Unexpected sync");
      },
      pull: async () => {
        throw new Error("Unexpected sync");
      },
      acknowledge: async () => {},
    },
    catalog: async () => ({
      version: 1,
      exercises: [],
      equipment: [],
      muscleGroups: [],
      aliases: [],
      exerciseMuscles: [],
      exerciseEquipment: [],
    }),
    deleteAccount: async () => {},
    exportAccount: async () => ({}),
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
      ["GET", "/v1/agent/capabilities"],
      ["POST", "/v1/agent/runs"],
      ["GET", `/v1/agent/runs/${crypto.randomUUID()}/events`],
      ["PUT", `/v1/agent/memories/${crypto.randomUUID()}`],
      ["GET", "/v1/progress/summary"],
      ["GET", "/v1/progress/activity"],
      ["GET", `/v1/progress/comparisons/${"a".repeat(64)}`],
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
        id: "00000000-0000-4000-8000-000000000001",
        version: 1,
        schemaVersion: 1,
        checksum: "sha256:abc",
        config: developmentPolicy,
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

  test("OpenAPI is available offline with sync success responses", () => {
    const spec = appWith().getOpenAPI31Document(openApiInfo);
    expect(spec.openapi).toBe("3.1.0");
    expect(
      spec.paths?.["/v1/sync/push"]?.post?.responses?.["200"],
    ).toBeDefined();
    expect(
      spec.paths?.["/v1/sync/push"]?.post?.responses?.["501"],
    ).toBeUndefined();
  });
});
