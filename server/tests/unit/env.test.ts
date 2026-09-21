import { expect, test } from "bun:test";
import { readEnv } from "../../src/config/env";

const base = {
  DATABASE_URL: "postgres://user:password@localhost/hybrd",
  BETTER_AUTH_URL: "https://api.example.test",
  BETTER_AUTH_SECRET: "unit-tests-only-unique-long-secret-value",
};

test("development auth is opt-in and cannot be enabled in production", () => {
  expect(readEnv(base).DEV_AUTH_ENABLED).toBe(false);
  expect(() =>
    readEnv({ ...base, NODE_ENV: "production", DEV_AUTH_ENABLED: "true" }),
  ).toThrow("forbidden");
  expect(() =>
    readEnv({
      ...base,
      NODE_ENV: "production",
      BETTER_AUTH_URL: "http://example.test",
    }),
  ).toThrow("HTTPS");
  expect(() => readEnv({ ...base, DEV_AUTH_ENABLED: "anything" })).toThrow();
});

test("optional integrations do not block local development but partial Apple config does", () => {
  expect(
    readEnv({ ...base, APPLE_CLIENT_ID: "", OPENROUTER_API_KEY: "" })
      .APPLE_CLIENT_ID,
  ).toBeUndefined();
  expect(() => readEnv({ ...base, APPLE_CLIENT_ID: "only-one-value" })).toThrow(
    "all three",
  );
});

test("validation errors never include credential values", () => {
  expect(() =>
    readEnv({ ...base, BETTER_AUTH_SECRET: "sensitive-short" }),
  ).toThrow("BETTER_AUTH_SECRET");
  try {
    readEnv({ ...base, BETTER_AUTH_SECRET: "sensitive-short" });
  } catch (error) {
    expect(String(error)).not.toContain("sensitive-short");
  }
});
