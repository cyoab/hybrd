import { readFileSync } from "node:fs";
import { connect } from "node:http2";
import { importPKCS8, SignJWT } from "jose";
import { ApiError } from "../api/errors";
import type { Env } from "../config/env";
export type PushKind = "sync_hint" | "coach_ready";
export type PushRequest = {
  id: string;
  token: string;
  environment: "sandbox" | "production";
  kind: PushKind;
};
export type PushResult = { status: number; reason?: string };
export interface PushProvider {
  available: boolean;
  send(input: PushRequest): Promise<PushResult>;
}
export function apnsProvider(env: Env): PushProvider {
  let jwt: { value: string; created: number } | undefined;
  async function token() {
    if (jwt && Date.now() - jwt.created < 3000000) return jwt.value;
    if (!env.APNS_PRIVATE_KEY_PATH || !env.APNS_KEY_ID || !env.APNS_TEAM_ID)
      throw new ApiError(
        503,
        "PUSH_NOT_CONFIGURED",
        "APNs credentials are not configured.",
      );
    const key = await importPKCS8(
      readFileSync(env.APNS_PRIVATE_KEY_PATH, "utf8"),
      "ES256",
    );
    const value = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: env.APNS_KEY_ID })
      .setIssuer(env.APNS_TEAM_ID)
      .setIssuedAt()
      .sign(key);
    jwt = { value, created: Date.now() };
    return value;
  }
  return {
    available: Boolean(
      env.APNS_KEY_ID &&
        env.APNS_TEAM_ID &&
        env.APNS_PRIVATE_KEY_PATH &&
        env.APNS_TOPIC,
    ),
    send: async (input) => {
      if (!env.APNS_TOPIC)
        throw new ApiError(
          503,
          "PUSH_NOT_CONFIGURED",
          "APNs is not configured.",
        );
      const authorization = await token();
      return new Promise((resolve, reject) => {
        const session = connect(
          input.environment === "production"
            ? "https://api.push.apple.com"
            : "https://api.sandbox.push.apple.com",
        );
        let settled = false;
        const done = (error?: Error, result?: PushResult) => {
          if (settled) return;
          settled = true;
          clearTimeout(timeout);
          session.destroy();
          if (error)
            reject(
              new ApiError(
                502,
                "PUSH_PROVIDER_UNAVAILABLE",
                "APNs could not complete this delivery.",
              ),
            );
          else if (result) resolve(result);
          else reject(new Error("Missing APNs result"));
        };
        const timeout = setTimeout(() => done(new Error("timeout")), 10000);
        session.on("error", (error) => done(error));
        const request = session.request({
          ":method": "POST",
          ":path": `/3/device/${input.token}`,
          authorization: `bearer ${authorization}`,
          "apns-topic": env.APNS_TOPIC,
          "apns-id": input.id,
          "apns-push-type": input.kind === "sync_hint" ? "background" : "alert",
          "apns-priority": input.kind === "sync_hint" ? "5" : "10",
          "apns-expiration": "0",
        });
        let status = 0,
          body = "";
        request.on("response", (headers) => {
          status = Number(headers[":status"]);
        });
        request.setEncoding("utf8");
        request.on("data", (chunk) => {
          body += chunk;
          if (body.length > 4096) done(new Error("oversized response"));
        });
        request.on("error", (error) => done(error));
        request.on("end", () => {
          let reason: string | undefined;
          try {
            const parsed = JSON.parse(body);
            if (typeof parsed.reason === "string")
              reason = parsed.reason.slice(0, 100);
          } catch {}
          done(undefined, { status, reason });
        });
        request.end(
          JSON.stringify(
            input.kind === "sync_hint"
              ? { aps: { "content-available": 1 } }
              : {
                  aps: {
                    alert: {
                      title: "hybrd",
                      body: "Your coach response is ready.",
                    },
                    sound: "default",
                  },
                },
          ),
        );
      });
    },
  };
}
