import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

export function createDatabase(url: string, max = 10) {
  // Drizzle changes postgres-js serializers. Keep its pool separate from raw transactions.
  const options = {
    max: Math.max(1, Math.floor(max / 2)),
    idle_timeout: 20,
    connect_timeout: 5,
  };
  const client = postgres(url, options);
  const ormClient = postgres(url, options);
  const db = drizzle(ormClient, { schema });
  return {
    db,
    client,
    close: async () => {
      await Promise.all([
        client.end({ timeout: 5 }),
        ormClient.end({ timeout: 5 }),
      ]);
    },
  };
}

export type Database = ReturnType<typeof createDatabase>["db"];
