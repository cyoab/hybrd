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
  const message = otpMessage("012345");
  expect(message.subject).not.toContain("012345");
  expect(message.html.match(/<title>(.*?)<\/title>/s)?.[1]).not.toContain(
    "012345",
  );
  expect(message.html.match(/<div[^>]*>(.*?)<\/div>/s)?.[1]).not.toContain(
    "012345",
  );
  expect(message.text).toContain("012345");
  // Preserve leading zeroes and a single selectable code, not separate digit cells.
  expect(message.html).toContain(">012345</p>");
  expect(message.text).toContain("10 minutes");
  expect(message.text).toContain("Never share");
  expect(message.text).toContain("ignore this email");
  expect(message.html).toContain('lang="en"');
  expect(message.html.match(/<h1\b/g)).toHaveLength(1);
  for (const table of message.html.matchAll(/<table\b[^>]*>/g)) {
    expect(table[0]).toContain('role="presentation"');
  }
  expect(message.html).toContain('alt=""');
});
test("email rejects malformed codes before interpolating HTML", () => {
  for (const code of [
    "<script>",
    "12345",
    "1234567",
    "123456\n",
    "１２３４５６",
  ])
    expect(() => otpMessage(code)).toThrow("Invalid authentication code");
});
test("email embeds a packaged PNG with no remote image or stylesheet dependency", async () => {
  const message = otpMessage("123456");
  expect(message.attachments).toHaveLength(1);
  const attachment = message.attachments[0];
  if (!attachment) throw new Error("Missing inline logo");
  expect(attachment.filename).toBe("hybrd-mark.png");
  expect(attachment.content_type).toBe("image/png");
  expect(message.html).toContain(`src="cid:${attachment.content_id}"`);
  const png = Buffer.from(attachment.content, "base64");
  expect(png.subarray(0, 8).toString("hex")).toBe("89504e470d0a1a0a");
  expect(png).toEqual(
    Buffer.from(
      await Bun.file(
        new URL("../../src/auth/emails/assets/hybrd-mark.png", import.meta.url),
      ).arrayBuffer(),
    ),
  );
  expect(message.html).not.toMatch(/(?:src|href)=["']https?:|url\(|@import/i);
  expect(message.html).not.toContain("data:image");
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
      expect(body.attachments).toEqual(otpMessage("123456").attachments);
      expect(body.html).toContain(
        `src="cid:${body.attachments[0].content_id}"`,
      );
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
  const bodies: string[] = [];
  await createOtpMailer(
    env,
    fake((url, init) => {
      expect(url).toBe("https://api.resend.com/emails");
      expect(init?.signal).toBeInstanceOf(AbortSignal);
      const headers = new Headers(init?.headers);
      expect(headers.get("authorization")).toBe("Bearer test-key");
      keys.push(headers.get("Idempotency-Key") ?? "");
      bodies.push(String(init?.body));
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
  expect(bodies[0]).toBe(bodies[1]);
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
