import { expect, test } from "bun:test";
import { createOtpMailer, otpMessage } from "../../src/auth/email";
import { readEnv } from "../../src/config/env";

const base = {
  DATABASE_URL: "postgres://test:test@localhost/hybrd_test",
  BETTER_AUTH_URL: "https://api.example.com",
  BETTER_AUTH_SECRET: "unit-tests-only-unique-long-secret-value",
};
const fake = (
  fn: (url: string, init?: RequestInit) => Promise<Response> | Response,
) =>
  ((url: unknown, init?: RequestInit) => fn(String(url), init)) as typeof fetch;
test("Google and email configuration fail closed when incomplete or unsafe", () => {
  expect(() => readEnv({ ...base, GOOGLE_IOS_CLIENT_ID: "only-ios" })).toThrow(
    "Google client",
  );
  expect(() => readEnv({ ...base, AUTH_EMAIL_TRANSPORT: "resend" })).toThrow(
    "Resend requires",
  );
  expect(() =>
    readEnv({
      ...base,
      NODE_ENV: "production",
      AUTH_EMAIL_TRANSPORT: "mailpit",
    }),
  ).toThrow("AUTH_EMAIL_TRANSPORT");
  expect(
    readEnv({
      ...base,
      AUTH_EMAIL_TRANSPORT: "resend",
      AUTH_EMAIL_FROM: "signin@example.com",
      RESEND_API_KEY: "test-key",
    }).AUTH_EMAIL_TRANSPORT,
  ).toBe("resend");
});
test("email has accessible HTML, plain text, clear expiry and no code in subject", () => {
  const message = otpMessage("123456");
  expect(message.subject).not.toContain("123456");
  expect(message.text).toContain("123456");
  expect(message.text).toContain("10 minutes");
  expect(message.html).toContain('lang="en"');
  expect(() => otpMessage("<script>")).toThrow();
});
test("Resend receives the authenticated sender, recipient and both email formats", async () => {
  const env = readEnv({
    ...base,
    AUTH_EMAIL_TRANSPORT: "resend",
    AUTH_EMAIL_FROM: "signin@example.com",
    RESEND_API_KEY: "test-key",
  });
  await createOtpMailer(
    env,
    fake((url, init) => {
      expect(url).toBe("https://api.resend.com/emails");
      const body = JSON.parse(String(init?.body));
      expect(body.from).toBe("hybrd <signin@example.com>");
      expect(body.to).toEqual(["athlete@example.test"]);
      expect(body.text).toContain("123456");
      expect(body.html).toContain("123456");
      expect(new Headers(init?.headers).get("authorization")).toBe(
        "Bearer test-key",
      );
      return Response.json({ id: "mail-id" });
    }),
  )("athlete@example.test", "123456");
});
test("Resend retries transient failures with the same idempotency key and bounded timeout", async () => {
  const env = readEnv({
    ...base,
    AUTH_EMAIL_TRANSPORT: "resend",
    AUTH_EMAIL_FROM: "signin@example.com",
    RESEND_API_KEY: "test-key",
  });
  const keys: string[] = [];
  await createOtpMailer(
    env,
    fake((url, init) => {
      expect(url).toBe("https://api.resend.com/emails");
      expect(init?.signal).toBeInstanceOf(AbortSignal);
      const headers = new Headers(init?.headers);
      expect(headers.get("authorization")).toBe("Bearer test-key");
      keys.push(headers.get("Idempotency-Key") ?? "");
      expect(JSON.parse(String(init?.body)).from).toBe(
        "hybrd <signin@example.com>",
      );
      return keys.length === 1
        ? new Response("private upstream error", { status: 503 })
        : Response.json({ id: "sent" });
    }),
  )("athlete@example.test", "123456");
  expect(keys).toHaveLength(2);
  expect(keys[0]).toBe(keys[1]);
  expect(keys[0]).toStartWith("auth-otp/");
});
test("permanent delivery failures are not retried or leaked, disabled transport never calls fetch", async () => {
  const env = readEnv({
    ...base,
    AUTH_EMAIL_TRANSPORT: "resend",
    AUTH_EMAIL_FROM: "signin@example.com",
    RESEND_API_KEY: "secret-key",
  });
  let calls = 0;
  await expect(
    createOtpMailer(
      env,
      fake(() => {
        calls++;
        return new Response("secret-key provider-error", { status: 401 });
      }),
    )("athlete@example.test", "123456"),
  ).rejects.toThrow("Email delivery unavailable.");
  expect(calls).toBe(1);
  await expect(
    createOtpMailer(
      readEnv(base),
      fake(() => {
        calls++;
        return new Response();
      }),
    )("athlete@example.test", "123456"),
  ).rejects.toThrow();
  expect(calls).toBe(1);
});
