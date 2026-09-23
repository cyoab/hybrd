import { afterAll, beforeAll, expect, spyOn, test } from "bun:test";
import { createHash } from "node:crypto";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { createApp } from "../../src/api/app";
import { createServices } from "../../src/api/services";
import { createAuth } from "../../src/auth";
import { authDigest } from "../../src/auth/otp-limit";
import { readEnv } from "../../src/config/env";
import { createDatabase } from "../../src/db/client";

const env = readEnv({
  ...process.env,
  DEV_AUTH_ENABLED: "false",
  AUTH_EMAIL_TRANSPORT: "mailpit",
  GOOGLE_CLIENT_ID: "google-web-test",
  GOOGLE_IOS_CLIENT_ID: "google-ios-test",
  GOOGLE_CLIENT_SECRET: "google-secret-test",
  APPLE_CLIENT_ID: "apple-service-test",
  APPLE_APP_BUNDLE_IDENTIFIER: "com.hybrd.test",
  APPLE_CLIENT_SECRET: "apple-secret-test",
});
if (
  env.NODE_ENV !== "test" ||
  !new URL(env.DATABASE_URL).pathname.endsWith("_test")
)
  throw new Error("Use the isolated test database.");
const database = createDatabase(env.DATABASE_URL);
const { client } = database;
const inbox = new Map<string, string>();
let failDelivery = false;
const mailer = async (email: string, otp: string) => {
  if (failDelivery)
    throw new Error("Private provider response with credentials");
  inbox.set(email, otp);
};
const auth = createAuth(env, database.db, { mailer });
const services = createServices(database, auth, { env });
const app = createApp(services, { logging: false });
const emails: string[] = [];
const newEmail = () => {
  const email = `${crypto.randomUUID()}@example.test`;
  emails.push(email);
  return email;
};
const post = (
  path: string,
  body: unknown,
  headers: Record<string, string> = {},
) =>
  app.request(`/api/auth${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      origin: env.BETTER_AUTH_URL,
      ...headers,
    },
    body: JSON.stringify(body),
  });
const send = (email: string) =>
  post("/email-otp/send-verification-otp", { email, type: "sign-in" });
const verify = (email: string, otp = inbox.get(email)) =>
  post("/sign-in/email-otp", { email, otp });
const ageCooldown = async (email: string) => {
  await client`update auth_otp_throttle set last_sent_at=now()-interval '61 seconds' where key=${authDigest(env.BETTER_AUTH_SECRET, `otp-email:${email}`)}`;
};
const nonce = "native-test-nonce-strong-random";
let keys: Awaited<ReturnType<typeof generateKeyPair>>;
let fetchSpy: ReturnType<typeof spyOn<typeof globalThis, "fetch">>;
beforeAll(async () => {
  keys = await generateKeyPair("RS256");
  const jwk = {
    ...(await exportJWK(keys.publicKey)),
    kid: "auth-test-key",
    alg: "RS256",
    use: "sig",
  };
  const realFetch = globalThis.fetch;
  fetchSpy = spyOn(globalThis, "fetch").mockImplementation(((
    url: unknown,
    init?: RequestInit,
  ) => {
    if (
      [
        "https://www.googleapis.com/oauth2/v3/certs",
        "https://appleid.apple.com/auth/keys",
      ].includes(String(url))
    )
      return Promise.resolve(Response.json({ keys: [jwk] }));
    return realFetch(url as string, init);
  }) as typeof fetch);
});
afterAll(async () => {
  fetchSpy.mockRestore();
  for (const email of emails) {
    await client`delete from auth_user where email=${email}`;
    await client`delete from auth_verification where identifier=${`sign-in-otp-${email}`}`;
    await client`delete from auth_otp_throttle where key=${authDigest(env.BETTER_AUTH_SECRET, `otp-email:${email}`)}`;
  }
  await database.close();
});
async function token(
  provider: "google" | "apple",
  email: string | undefined,
  claims: Record<string, unknown> = {},
) {
  return new SignJWT({
    email,
    email_verified: provider === "apple" ? "true" : true,
    name: "Athlete",
    nonce,
    iss:
      provider === "google"
        ? "https://accounts.google.com"
        : "https://appleid.apple.com",
    aud:
      provider === "google"
        ? env.GOOGLE_IOS_CLIENT_ID
        : env.APPLE_APP_BUNDLE_IDENTIFIER,
    sub: email ?? crypto.randomUUID(),
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 600,
    ...claims,
  })
    .setProtectedHeader({ alg: "RS256", kid: "auth-test-key" })
    .sign(keys.privateKey);
}
const social = (
  provider: "google" | "apple",
  token: string,
  originalNonce = nonce,
) =>
  post("/sign-in/social", {
    provider,
    idToken: { token, nonce: originalNonce },
  });

test("public auth methods expose configuration without secrets and passwords are disabled", async () => {
  const result = await app.request("/api/auth/methods");
  expect(await result.json()).toEqual({
    google: true,
    apple: true,
    emailOtp: true,
    otp: {
      length: 6,
      expiresInSeconds: 600,
      resendAfterSeconds: 60,
      maxSendsPerHour: 3,
    },
  });
  expect(result.headers.get("Cache-Control")).toBe("no-store");
  expect(
    (
      await post("/sign-up/email", {
        email: newEmail(),
        name: "Test",
        password: "test-password",
      })
    ).status,
  ).toBe(400);
  expect(
    (
      await post("/sign-in/email", {
        email: newEmail(),
        password: "test-password",
      })
    ).status,
  ).toBe(400);
});
test("OTP registers a verified user and one athlete, supports bearer access, logout and returning sign-in", async () => {
  const email = newEmail();
  expect((await send(`  ${email.toUpperCase()}  `)).status).toBe(200);
  expect(inbox.get(email)).toMatch(/^\d{6}$/);
  const [stored] =
    await client`select value from auth_verification where identifier=${`sign-in-otp-${email}`}`;
  expect(stored?.value).toBe(
    `${authDigest(env.BETTER_AUTH_SECRET, `otp-code:${inbox.get(email)}`)}:0`,
  );
  const first = await verify(email.toUpperCase(), inbox.get(email));
  expect(first.status).toBe(200);
  const account = await first.json();
  expect(account.user.emailVerified).toBe(true);
  expect(account.user.email).toBe(email);
  const headers = { authorization: `Bearer ${account.token}` };
  expect((await app.request("/v1/bootstrap", { headers })).status).toBe(200);
  expect((await post("/sign-out", {}, headers)).status).toBe(200);
  expect((await app.request("/v1/bootstrap", { headers })).status).toBe(401);
  await ageCooldown(email);
  expect((await send(email)).status).toBe(200);
  const returning = await (await verify(email)).json();
  expect(returning.user.id).toBe(account.user.id);
  const [{ count } = {}] =
    await client`select count(*)::integer as count from athletes where auth_user_id=${account.user.id}`;
  expect(count).toBe(1);
});
test("only one concurrent verification can consume an OTP and replay fails", async () => {
  const email = newEmail();
  await send(email);
  const results = await Promise.all([verify(email), verify(email)]);
  expect(results.map((r) => r.status).sort()).toEqual([200, 400]);
  expect((await verify(email)).status).toBe(400);
});
test("expired codes cannot authenticate", async () => {
  const email = newEmail();
  await send(email);
  await client`update auth_verification set expires_at=now()-interval '1 second' where identifier=${`sign-in-otp-${email}`}`;
  expect((await verify(email)).status).toBe(400);
});
test("five incorrect attempts exhaust a code", async () => {
  const email = newEmail();
  await send(email);
  const wrong = inbox.get(email) === "000000" ? "111111" : "000000";
  for (let n = 0; n < 5; n++)
    expect((await verify(email, wrong)).status).toBe(400);
  expect((await verify(email)).status).toBe(403);
  expect((await verify(email)).status).toBe(400);
});
test("resend throttle is per normalized email across auth instances and preserves the pending code", async () => {
  const email = newEmail();
  await send(email);
  const code = inbox.get(email);
  const second = createAuth(env, database.db, { mailer });
  const limited = await second.handler(
    new Request(
      `${env.BETTER_AUTH_URL}/api/auth/email-otp/send-verification-otp`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-forwarded-for": "203.0.113.5",
        },
        body: JSON.stringify({ email: email.toUpperCase(), type: "sign-in" }),
      },
    ),
  );
  expect(limited.status).toBe(429);
  expect(Number(limited.headers.get("Retry-After"))).toBeGreaterThan(0);
  expect(inbox.get(email)).toBe(code);
  expect((await verify(email, code)).status).toBe(200);
});
test("rotation invalidates the previous code and hourly quota cannot be bypassed by cooldown", async () => {
  const email = newEmail();
  await send(email);
  const previous = inbox.get(email);
  await ageCooldown(email);
  expect((await send(email)).status).toBe(200);
  const current = inbox.get(email);
  // Extremely rare random equality is valid; only test distinct challenges.
  if (previous !== current)
    expect((await verify(email, previous)).status).toBe(400);
  expect((await verify(email, current)).status).toBe(200);
  await ageCooldown(email);
  expect((await send(email)).status).toBe(200);
  await ageCooldown(email);
  const limited = await send(email);
  expect(limited.status).toBe(429);
  expect(Number(limited.headers.get("Retry-After"))).toBeGreaterThan(60);
  await client`update auth_otp_throttle set window_start=now()-interval '61 minutes' where key=${authDigest(env.BETTER_AUTH_SECRET, `otp-email:${email}`)}`;
  expect((await send(email)).status).toBe(200);
});
test("delivery failures are sanitized, invalidate the code, and create no user", async () => {
  const email = newEmail();
  failDelivery = true;
  let result: Response;
  try {
    result = await send(email);
  } finally {
    failDelivery = false;
  }
  expect(result.status).toBe(503);
  expect(await result.text()).not.toContain("credentials");
  expect(
    await client`select id from auth_verification where identifier=${`sign-in-otp-${email}`}`,
  ).toHaveLength(0);
  expect(
    await client`select id from auth_user where email=${email}`,
  ).toHaveLength(0);
});
test("unused OTP endpoints, invalid inputs and untrusted origins are rejected", async () => {
  const email = newEmail();
  expect(
    (
      await post("/email-otp/send-verification-otp", {
        email,
        type: "forget-password",
      })
    ).status,
  ).toBe(400);
  expect((await send("invalid")).status).toBe(400);
  expect((await verify(email, "12345")).status).toBe(400);
  expect(
    (
      await post("/sign-in/email-otp", {
        email,
        otp: "123456",
        emailVerified: true,
      })
    ).status,
  ).toBe(400);
  expect(
    (
      await post("/email-otp/check-verification-otp", {
        email,
        otp: "123456",
        type: "sign-in",
      })
    ).status,
  ).toBe(404);
  expect(
    (
      await post(
        "/email-otp/send-verification-otp",
        { email, type: "sign-in" },
        { origin: "https://untrusted.example" },
      )
    ).status,
  ).toBe(403);
});
test("unconfigured sign-in methods report unavailable without sending", async () => {
  const disabledEnv = {
    ...env,
    AUTH_EMAIL_TRANSPORT: "disabled" as const,
    GOOGLE_CLIENT_ID: undefined,
    GOOGLE_CLIENT_SECRET: undefined,
    GOOGLE_IOS_CLIENT_ID: undefined,
    APPLE_CLIENT_ID: undefined,
    APPLE_CLIENT_SECRET: undefined,
    APPLE_APP_BUNDLE_IDENTIFIER: undefined,
  };
  const disabled = createAuth(disabledEnv, database.db);
  const methods = await disabled.handler(
    new Request(`${env.BETTER_AUTH_URL}/api/auth/methods`),
  );
  expect(await methods.json()).toMatchObject({
    google: false,
    apple: false,
    emailOtp: false,
  });
  const response = await disabled.handler(
    new Request(
      `${env.BETTER_AUTH_URL}/api/auth/email-otp/send-verification-otp`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email: newEmail(), type: "sign-in" }),
      },
    ),
  );
  expect(response.status).toBe(503);
});
test("Google verifies signed native tokens for both configured audiences and reuses the account", async () => {
  const email = newEmail();
  const first = await social("google", await token("google", email));
  expect(first.status).toBe(200);
  const account = await first.json();
  const second = await social(
    "google",
    await token("google", email, { aud: env.GOOGLE_CLIENT_ID }),
  );
  expect(second.status).toBe(200);
  expect((await second.json()).user.id).toBe(account.user.id);
  expect(
    (
      await app.request("/v1/bootstrap", {
        headers: { authorization: `Bearer ${account.token}` },
      })
    ).status,
  ).toBe(200);
});
test("Apple supports SHA256 nonce, private relay email and returning tokens without email", async () => {
  const email = newEmail();
  const first = await social(
    "apple",
    await token("apple", email, {
      nonce: createHash("sha256").update(nonce).digest("hex"),
      is_private_email: "true",
    }),
  );
  expect(first.status).toBe(200);
  const account = await first.json();
  const returning = await social(
    "apple",
    await token("apple", undefined, { sub: email, email_verified: undefined }),
  );
  expect(returning.status).toBe(200);
  expect((await returning.json()).user.id).toBe(account.user.id);
  const unknown = await social("apple", await token("apple", undefined));
  expect(unknown.status).toBe(401);
});
test("verified matching emails link Google, Apple and OTP to one athlete", async () => {
  const email = newEmail();
  await send(email);
  const original = await (await verify(email)).json();
  for (const provider of ["google", "apple"] as const) {
    const response = await social(provider, await token(provider, email));
    expect(response.status).toBe(200);
    expect((await response.json()).user.id).toBe(original.user.id);
  }
  expect(
    await client`select id from athletes where auth_user_id=${original.user.id}`,
  ).toHaveLength(1);
  expect(
    await client`select id from auth_account where user_id=${original.user.id}`,
  ).toHaveLength(2);
});
test("unverified provider email cannot create or link an identity", async () => {
  const email = newEmail();
  for (const provider of ["google", "apple"] as const) {
    expect(
      (
        await social(
          provider,
          await token(provider, email, { email_verified: false }),
        )
      ).status,
    ).toBe(403);
  }
  expect(
    await client`select id from auth_user where email=${email}`,
  ).toHaveLength(0);
  await send(email);
  await verify(email);
  expect(
    (
      await social(
        "google",
        await token("google", email, { email_verified: false }),
      )
    ).status,
  ).toBeGreaterThanOrEqual(400);
});

test("provider sign-in cannot take over an existing unverified local account", async () => {
  const email = newEmail();
  const local = createAuth({ ...env, DEV_AUTH_ENABLED: true }, database.db, {
    mailer,
  });
  const account = await local.api.signUpEmail({
    body: { email, name: "Unverified", password: "test-password-only" },
  });
  expect(account.user.emailVerified).toBe(false);
  expect(
    (await social("google", await token("google", email))).status,
  ).toBeGreaterThanOrEqual(400);
  expect(
    await client`select id from auth_account where user_id=${account.user.id} and provider_id='google'`,
  ).toHaveLength(0);
  // Proving mailbox ownership enables linking and revokes unproven sessions.
  await send(email);
  expect((await verify(email)).status).toBe(200);
  expect(
    (
      await app.request("/v1/bootstrap", {
        headers: { authorization: `Bearer ${account.token}` },
      })
    ).status,
  ).toBe(401);
  const linked = await social("google", await token("google", email));
  expect(linked.status).toBe(200);
  expect((await linked.json()).user.id).toBe(account.user.id);
});

test("concurrent sends reserve one challenge and a failed delivery cannot affect another request", async () => {
  const email = newEmail();
  expect(
    (await Promise.all([send(email), send(email)])).map((r) => r.status).sort(),
  ).toEqual([200, 429]);
  const other = newEmail();
  const mixed = createAuth(env, database.db, {
    mailer: async (address, otp) => {
      if (address === other) throw new Error("Private delivery failure");
      inbox.set(address, otp);
    },
  });
  const good = newEmail();
  const responses = await Promise.all(
    [other, good].map((address) =>
      mixed.api.sendVerificationOTP({
        body: { email: address, type: "sign-in" },
        asResponse: true,
      }),
    ),
  );
  expect(responses.map((r) => r.status)).toEqual([503, 200]);
  expect((await verify(good)).status).toBe(200);
});
test("both providers reject wrong audience, issuer, expiry, nonce and signature", async () => {
  const email = newEmail();
  for (const provider of ["google", "apple"] as const) {
    for (const claims of [
      { aud: "attacker-client" },
      { iss: "https://attacker.example" },
      { exp: Math.floor(Date.now() / 1000) - 3600 },
      { nonce: "wrong-nonce" },
    ])
      expect(
        (await social(provider, await token(provider, email, claims))).status,
      ).toBe(401);
    const signed = await token(provider, email),
      parts = signed.split(".");
    parts[2] = `${parts[2]?.startsWith("a") ? "b" : "a"}${parts[2]?.slice(1)}`;
    expect((await social(provider, parts.join("."))).status).toBe(401);
    expect(
      (await post("/sign-in/social", { provider, idToken: { token: signed } }))
        .status,
    ).toBe(400);
  }
  expect(
    await client`select id from auth_user where email=${email}`,
  ).toHaveLength(0);
});
