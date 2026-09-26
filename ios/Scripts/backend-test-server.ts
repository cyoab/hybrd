// Isolated native integration harness. Never mounted by the normal API entry point.
import { createApp } from "../../server/src/api/app";
import { createServices } from "../../server/src/api/services";
import { createAuth } from "../../server/src/auth";
import { readEnv } from "../../server/src/config/env";
import { createDatabase } from "../../server/src/db/client";
const env = readEnv({ ...process.env, DEV_AUTH_ENABLED: "false", AUTH_EMAIL_TRANSPORT: "resend",
  RESEND_API_KEY: "injected-test-mailer", AUTH_EMAIL_FROM: "test@example.com",
  GOOGLE_CLIENT_ID: undefined, GOOGLE_CLIENT_SECRET: undefined, GOOGLE_IOS_CLIENT_ID: undefined,
  APPLE_CLIENT_ID: undefined, APPLE_CLIENT_SECRET: undefined, APPLE_APP_BUNDLE_IDENTIFIER: undefined,
  STRAVA_CLIENT_ID: undefined, STRAVA_CLIENT_SECRET: undefined, OPENROUTER_API_KEY: undefined,
});
if (env.NODE_ENV !== "test" || !new URL(env.DATABASE_URL).pathname.endsWith("_test")) throw new Error("Requires isolated test database");
const database = createDatabase(env.DATABASE_URL);
const inbox = new Map<string, string>();
const auth = createAuth(env, database.db, { mailer: async (email, otp) => { inbox.set(email, otp); } });
const app = createApp(createServices(database, auth, { env }), { logging: false });
Bun.serve({ hostname: "0.0.0.0", port: 3011, async fetch(request) {
  const url = new URL(request.url);
  if (url.pathname === "/test/inbox") {
    const email = url.searchParams.get("email") ?? "";
    return Response.json({ otp: inbox.get(email) ?? null });
  }
  if (url.pathname === "/test/cleanup" && request.method === "POST") {
    const { email } = await request.json();
    if (!inbox.has(email)) return new Response(null, { status: 403 });
    await database.client`delete from auth_user where email=${email}`;
    inbox.delete(email); return Response.json({ success: true });
  }
  return app.fetch(request);
}});
console.info("Isolated native test backend ready on port 3011; no real email delivery.");
