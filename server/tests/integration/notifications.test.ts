import { afterAll, expect, test } from "bun:test";
import type { PushResult } from "../../src/notifications/provider";
import { notificationServices } from "../../src/notifications/service";
import { harness, uuid } from "./helpers";

const h = harness();
afterAll(() => h.close());
let calls = 0,
  result: PushResult = { status: 200 };
const service = notificationServices(h.database.client, {
  available: true,
  send: async () => {
    calls++;
    return result;
  },
});
test("push delivery requires an owned enabled device, deduplicates and clears invalid tokens", async () => {
  const a = await h.account(),
    b = await h.account(),
    id = uuid();
  await expect(
    service.send(a.userId, a.deviceId, id, "sync_hint"),
  ).rejects.toThrow("not enabled");
  await h.services.registerDevice(a.userId, a.deviceId, {
    appVersion: "1.0",
    pushEnabled: true,
    pushToken: "a".repeat(64),
    pushEnvironment: "sandbox",
  });
  await expect(
    service.send(b.userId, a.deviceId, id, "sync_hint"),
  ).rejects.toThrow("not enabled");
  expect(
    (await service.send(a.userId, a.deviceId, id, "sync_hint")).status,
  ).toBe("sent");
  const before = calls;
  expect(
    (await service.send(a.userId, a.deviceId, id, "sync_hint")).status,
  ).toBe("sent");
  expect(calls).toBe(before);
  await expect(
    service.send(a.userId, a.deviceId, id, "coach_ready"),
  ).rejects.toThrow("new delivery ID");
  result = { status: 410, reason: "Unregistered" };
  expect(
    (await service.send(a.userId, a.deviceId, uuid(), "sync_hint")).status,
  ).toBe("failed");
  const [device] = await h.database
    .client`select push_enabled,push_token,revoked_at from device_installations where id=${a.deviceId}`;
  expect(device?.push_enabled).toBe(false);
  expect(device?.push_token).toBeNull();
  expect(device?.revoked_at).toBeNull();
});
