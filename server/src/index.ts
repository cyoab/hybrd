import { createApp } from "./api/app";
import { createServices } from "./api/services";
import { createAuth } from "./auth";
import { readEnv } from "./config/env";
import { createDatabase } from "./db/client";
import { stravaProvider } from "./strava/provider";
import { startStravaWorker } from "./strava/worker";
import { log } from "./telemetry/logger";

const env = readEnv();
const database = createDatabase(env.DATABASE_URL);
const auth = createAuth(env, database.db);
const app = createApp(createServices(database, auth, { env }), {
  peerAddress: (request) => server.requestIP(request)?.address,
  trustedOrigins: [
    env.BETTER_AUTH_URL,
    ...env.TRUSTED_ORIGINS.split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  ],
});

const server = Bun.serve({
  idleTimeout: 60,
  hostname: env.HOST,
  port: env.PORT,
  fetch: app.fetch,
});
log({ event: "server_started", port: server.port });
const stopStrava = env.STRAVA_CLIENT_ID
  ? startStravaWorker(database.client, env, stravaProvider(env))
  : async () => {};

let stopping = false;
async function shutdown() {
  if (stopping) return;
  stopping = true;
  const deadline = setTimeout(() => process.exit(1), 35000);
  deadline.unref();
  await server.stop();
  await stopStrava();
  await database.close();
  clearTimeout(deadline);
}
process.on("SIGTERM", () => void shutdown());
process.on("SIGINT", () => void shutdown());
