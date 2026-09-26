import { z } from "zod";
import type { Env } from "../config/env";

export const RemoteId = z.union([
  z.string().regex(/^\d+$/),
  z.number().int().nonnegative().safe().transform(String),
]);
const Tokens = z.object({
  access_token: z.string().min(1),
  refresh_token: z.string().min(1),
  expires_at: z.number().int().positive(),
  athlete: z.object({ id: RemoteId }).optional(),
});
export const Activity = z.object({
  id: RemoteId,
  sport_type: z.string().optional(),
  type: z.string().optional(),
  start_date: z.iso.datetime(),
  distance: z.number().nonnegative(),
  elapsed_time: z.number().int().nonnegative(),
  moving_time: z.number().int().nonnegative(),
  manual: z.boolean().optional(),
  flagged: z.boolean().optional(),
  average_heartrate: z.number().nullable().optional(),
  max_heartrate: z.number().nullable().optional(),
  description: z.string().nullable().optional(),
});
export const Effort = z.object({
  distance: z.number().positive(),
  elapsed_time: z.number().int().positive(),
  name: z.string(),
  start_date: z.iso.datetime().optional(),
});
export type StravaActivity = z.infer<typeof Activity>;
export class StravaError extends Error {
  constructor(
    public readonly code: string,
    public readonly retryAfter = 0,
    public readonly ambiguous = false,
  ) {
    super(code);
  }
}
export type PublishActivity = {
  name: string;
  sport_type: "Run" | "WeightTraining";
  start_date_local: string;
  elapsed_time: number;
  distance?: number;
  description: string;
};
export function stravaProvider(env: Env, fetcher: typeof fetch = fetch) {
  async function call(
    path: string,
    method: string,
    access?: string,
    body?: URLSearchParams,
    uncertain = false,
    basic = false,
  ) {
    const headers: Record<string, string> = {};
    if (access) headers.Authorization = `Bearer ${access}`;
    if (basic)
      headers.Authorization = `Basic ${Buffer.from(`${env.STRAVA_CLIENT_ID}:${env.STRAVA_CLIENT_SECRET}`).toString("base64")}`;
    let r: Response;
    try {
      r = await fetcher(`https://www.strava.com${path}`, {
        method,
        headers,
        body,
        signal: AbortSignal.timeout(10_000),
        redirect: "error",
      });
    } catch {
      throw new StravaError("STRAVA_NETWORK_ERROR", 60, uncertain);
    }
    if (!r.ok) {
      await r.body?.cancel();
      if (r.status === 429)
        throw new StravaError(
          "STRAVA_RATE_LIMITED",
          Math.max(
            60,
            Math.min(86400, Number(r.headers.get("Retry-After")) || 900),
          ),
        );
      if (r.status === 401)
        throw new StravaError("STRAVA_REAUTHENTICATION_REQUIRED");
      if (r.status === 400 && body?.get("grant_type") === "refresh_token")
        throw new StravaError("STRAVA_REAUTHENTICATION_REQUIRED");
      if (r.status === 403) throw new StravaError("STRAVA_SCOPE_REQUIRED");
      if (r.status === 404) throw new StravaError("STRAVA_NOT_FOUND");
      throw new StravaError(
        "STRAVA_REQUEST_FAILED",
        r.status >= 500 ? 60 : 0,
        uncertain && r.status >= 500,
      );
    }
    try {
      const text = await r.text();
      return text ? JSON.parse(text) : {};
    } catch {
      throw new StravaError("STRAVA_INVALID_RESPONSE", 60, uncertain);
    }
  }
  return {
    available: Boolean(env.STRAVA_CLIENT_ID && env.STRAVA_CLIENT_SECRET),
    exchange: async (code: string) =>
      Tokens.parse(
        await call(
          "/oauth/token",
          "POST",
          undefined,
          new URLSearchParams({
            client_id: env.STRAVA_CLIENT_ID ?? "",
            client_secret: env.STRAVA_CLIENT_SECRET ?? "",
            grant_type: "authorization_code",
            code,
          }),
        ),
      ),
    refresh: async (refresh: string) =>
      Tokens.parse(
        await call(
          "/oauth/token",
          "POST",
          undefined,
          new URLSearchParams({
            client_id: env.STRAVA_CLIENT_ID ?? "",
            client_secret: env.STRAVA_CLIENT_SECRET ?? "",
            grant_type: "refresh_token",
            refresh_token: refresh,
          }),
        ),
      ),
    revoke: async (token: string) => {
      await call(
        "/oauth/revoke",
        "POST",
        undefined,
        new URLSearchParams({ token, token_type_hint: "refresh_token" }),
        false,
        true,
      );
    },
    profile: async (token: string) =>
      z
        .object({
          firstname: z.string().trim().min(1).max(40).nullable().catch(null),
          weight: z.number().min(20).max(400).nullable().catch(null),
        })
        .parse(await call("/api/v3/athlete", "GET", token)),
    zones: async (token: string) =>
      z
        .object({
          heart_rate: z
            .object({
              custom_zones: z.boolean(),
              zones: z
                .array(z.object({ min: z.number(), max: z.number() }))
                .max(10),
            })
            .optional(),
        })
        .parse(await call("/api/v3/athlete/zones", "GET", token)),
    activities: async (
      token: string,
      after: number,
      before: number,
      page: number,
    ) =>
      z
        .array(Activity)
        .max(200)
        .parse(
          await call(
            `/api/v3/athlete/activities?after=${after}&before=${before}&page=${page}&per_page=200`,
            "GET",
            token,
          ),
        ),
    detail: async (token: string, id: string) =>
      Activity.extend({ best_efforts: z.array(Effort).default([]) }).parse(
        await call(
          `/api/v3/activities/${encodeURIComponent(id)}`,
          "GET",
          token,
        ),
      ),
    publish: async (token: string, activity: PublishActivity) => {
      const result = await call(
        "/api/v3/activities",
        "POST",
        token,
        new URLSearchParams(
          Object.fromEntries(
            Object.entries(activity).map(([k, v]) => [k, String(v)]),
          ),
        ),
        true,
      );
      const parsed = z.object({ id: RemoteId }).safeParse(result);
      if (!parsed.success)
        throw new StravaError("STRAVA_INVALID_RESPONSE", 0, true);
      return parsed.data.id;
    },
  };
}
export type StravaProvider = ReturnType<typeof stravaProvider>;
