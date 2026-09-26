import { afterAll, expect, test } from "bun:test";
import type {
  JWSRenewalInfoDecodedPayload,
  JWSTransactionDecodedPayload,
  ResponseBodyV2DecodedPayload,
} from "@apple/app-store-server-library";
import { ApiError } from "../../src/api/errors";
import type { AppleVerifier } from "../../src/billing/verifier";
import { readEnv } from "../../src/config/env";
import { harness, uuid } from "./helpers";

const transactions = new Map<string, JWSTransactionDecodedPayload>(),
  notifications = new Map<string, ResponseBodyV2DecodedPayload>(),
  renewals = new Map<string, JWSRenewalInfoDecodedPayload>();
function get<T>(map: Map<string, T>, key: string) {
  const value = map.get(key);
  if (!value)
    throw new ApiError(400, "INVALID_APPLE_SIGNATURE", "Unverified payload.");
  return value;
}
const verifier: AppleVerifier = {
  available: true,
  transaction: async (s) => get(transactions, s),
  notification: async (s) => get(notifications, s),
  renewal: async (s) => get(renewals, s),
};
const env = {
  ...readEnv(),
  STOREKIT_BUNDLE_ID: "test.hybrd",
  STOREKIT_PRODUCTS: JSON.stringify({ "test.pro": "pro" }),
};
const h = harness({ env, apple: verifier });
afterAll(() => h.close());
function txn(
  athleteId: string,
  overrides: Partial<JWSTransactionDecodedPayload> = {},
) {
  const now = Date.now();
  return {
    transactionId: uuid(),
    originalTransactionId: uuid(),
    bundleId: env.STOREKIT_BUNDLE_ID,
    productId: "test.pro",
    appAccountToken: athleteId,
    environment: "Sandbox",
    purchaseDate: now - 1000,
    expiresDate: now + 86400000,
    signedDate: now,
    type: "Auto-Renewable Subscription",
    ...overrides,
  };
}
async function submit(
  a: Awaited<ReturnType<typeof h.account>>,
  t: JWSTransactionDecodedPayload,
) {
  const key = uuid();
  transactions.set(key, t);
  return a.send("/v1/billing/apple/transactions", { signedTransaction: key });
}
async function notify(
  t: JWSTransactionDecodedPayload,
  type: string,
  signedDate: number,
  renewal?: JWSRenewalInfoDecodedPayload,
) {
  const key = uuid(),
    tx = uuid(),
    rn = uuid();
  transactions.set(tx, t);
  if (renewal) renewals.set(rn, renewal);
  notifications.set(key, {
    notificationUUID: uuid(),
    notificationType: type,
    signedDate,
    data: {
      signedTransactionInfo: tx,
      signedRenewalInfo: renewal ? rn : undefined,
    },
  });
  const send = () =>
    h.app.request("/webhooks/apple", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ signedPayload: key }),
    });
  return { response: await send(), send };
}
test("purchase ownership, signature rejection, product/bundle/environment validation and restore replay", async () => {
  const a = await h.account(),
    b = await h.account(),
    t = txn(a.athleteId);
  expect(
    (
      await a.send("/v1/billing/apple/transactions", {
        signedTransaction: "forged",
      })
    ).status,
  ).toBe(400);
  for (const bad of [
    { bundleId: "wrong" },
    { environment: "Production" },
    { productId: "unknown" },
    { appAccountToken: undefined },
  ])
    expect((await submit(a, { ...t, ...bad })).status).toBe(400);
  expect((await submit(b, t)).status).toBe(403);
  const first = await submit(a, t);
  expect(first.status).toBe(200);
  expect((await first.json()).entitlements[0].status).toBe("active");
  expect((await submit(a, t)).status).toBe(200);
  const [count] = await h.database
    .client`select count(*)::int as n from storekit_transactions where athlete_id=${a.athleteId}`;
  expect(count?.n).toBe(1);
  expect(
    (
      await submit(b, {
        ...t,
        appAccountToken: b.athleteId,
        signedDate: Date.now() + 1,
      })
    ).status,
  ).toBe(409);
});
test("out-of-order refund/renewal notifications, grace, expiration and duplicate webhook", async () => {
  const a = await h.account(),
    now = Date.now(),
    t = txn(a.athleteId, {
      expiresDate: now - 100,
      purchaseDate: now - 86400000,
      signedDate: now,
    });
  expect((await submit(a, t)).status).toBe(200);
  const grace = await notify(t, "DID_FAIL_TO_RENEW", now + 1, {
    originalTransactionId: t.originalTransactionId,
    environment: "Sandbox",
    isInBillingRetryPeriod: true,
    gracePeriodExpiresDate: now + 86400000,
    signedDate: now + 1,
  });
  expect(grace.response.status).toBe(204);
  expect((await grace.send()).status).toBe(204);
  expect((await h.services.entitlements(a.userId))[0]?.status).toBe("grace");
  expect(
    (await notify({ ...t, revocationDate: now + 2 }, "REFUND", now + 2))
      .response.status,
  ).toBe(204);
  expect((await h.services.entitlements(a.userId))[0]?.status).toBe("revoked");
  await notify(t, "DID_RENEW", now + 1);
  expect((await h.services.entitlements(a.userId))[0]?.status).toBe("revoked");
  await submit(a, { ...t, signedDate: now + 3 });
  expect((await h.services.entitlements(a.userId))[0]?.status).toBe("revoked");
  const renewed = txn(a.athleteId, {
    originalTransactionId: t.originalTransactionId,
    signedDate: now + 4,
  });
  await notify(renewed, "DID_RENEW", now + 4);
  expect((await h.services.entitlements(a.userId))[0]?.status).toBe("active");
  await h.database
    .client`update storekit_transactions set expires_at=now()-interval '1 second',grace_until=null where athlete_id=${a.athleteId}`;
  expect((await h.services.entitlements(a.userId))[0]?.status).toBe("expired");
});
test("revoking the latest renewal does not reactivate an earlier overlapping transaction", async () => {
  const a = await h.account(),
    now = Date.now(),
    old = txn(a.athleteId, { purchaseDate: now - 5000 });
  await submit(a, old);
  const latest = txn(a.athleteId, {
    originalTransactionId: old.originalTransactionId,
    purchaseDate: now - 1000,
    signedDate: now + 1,
  });
  await submit(a, latest);
  await notify({ ...latest, revocationDate: now + 2 }, "REFUND", now + 2);
  expect((await h.services.entitlements(a.userId))[0]?.status).toBe("revoked");
});
test("deleted accounts are not resurrected by delayed Apple notifications", async () => {
  const a = await h.account(),
    t = txn(a.athleteId);
  await submit(a, t);
  expect((await a.send("/v1/account", undefined, "DELETE")).status).toBe(204);
  expect((await notify(t, "DID_RENEW", Date.now() + 5)).response.status).toBe(
    204,
  );
  const rows = await h.database
    .client`select * from storekit_transactions where athlete_id=${a.athleteId}`;
  expect(rows).toHaveLength(0);
});

test("overlapping subscription chains retain the longest current entitlement", async () => {
  const a = await h.account(),
    now = Date.now(),
    long = txn(a.athleteId, {
      expiresDate: now + 864000000,
      purchaseDate: now - 10000,
    }),
    short = txn(a.athleteId, {
      expiresDate: now + 3600000,
      purchaseDate: now - 1000,
    });
  await submit(a, long);
  await submit(a, short);
  const current = (await h.services.entitlements(a.userId))[0];
  expect(current?.validUntil).toBe(new Date(long.expiresDate).toISOString());
  await notify({ ...short, revocationDate: now + 5 }, "REFUND", now + 5);
  expect((await h.services.entitlements(a.userId))[0]?.status).toBe("active");
});
