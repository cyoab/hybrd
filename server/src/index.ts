import { createApp } from "./api/app";
import { createServices } from "./api/services";
import { createAuth } from "./auth";
import { readEnv } from "./config/env";
import { createDatabase } from "./db/client";
import { log } from "./telemetry/logger";

const env = readEnv();
const database = createDatabase(env.DATABASE_URL);
const auth = createAuth(env, database.db);
const app = createApp(createServices(database, auth), {
  trustedOrigins: [
    env.BETTER_AUTH_URL,
    ...env.TRUSTED_ORIGINS.split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  ],
});

const server = Bun.serve({
  hostname: env.HOST,
  port: env.PORT,
  fetch: app.fetch,
});
log({ event: "server_started", port: server.port });

let stopping = false;
async function shutdown() {
  if (stopping) return;
  stopping = true;
  const deadline = setTimeout(() => process.exit(1), 10000);
  deadline.unref();
  await server.stop();
  await database.close();
  clearTimeout(deadline);
}
process.on("SIGTERM", () => void shutdown());
process.on("SIGINT", () => void shutdown());
