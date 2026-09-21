import { migrate } from "drizzle-orm/postgres-js/migrator";
import { createDatabase } from "./client";

const url = process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL is required to run migrations.");
const database = createDatabase(url, 1);
try {
  await migrate(database.db, {
    migrationsFolder: new URL("../../migrations", import.meta.url).pathname,
  });
  console.info("Database migrations applied.");
} finally {
  await database.close();
}
