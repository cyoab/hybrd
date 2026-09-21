import { seedCatalog } from "../catalog/service";
import { developmentPolicy, policyChecksum } from "../config/policy";
import { createDatabase } from "./client";
import { trainingPolicyVersions } from "./schema";

if (!["development", "test"].includes(process.env.NODE_ENV ?? "")) {
  throw new Error("Development fixtures require NODE_ENV=development or test.");
}
const url = process.env.DATABASE_URL;
if (!url)
  throw new Error("DATABASE_URL is required to seed development fixtures.");
const database = createDatabase(url, 1);
try {
  await database.db
    .insert(trainingPolicyVersions)
    .values({
      id: "00000000-0000-4000-8000-000000000002",
      version: 2,
      schemaVersion: 1,
      status: "published",
      config: developmentPolicy,
      checksum: policyChecksum(developmentPolicy),
      publishedAt: new Date("2026-09-21T00:00:00Z"),
    })
    .onConflictDoNothing();
  await seedCatalog(database.client);
  console.info(
    "Development policy seeded. No user accounts or training records created.",
  );
} finally {
  await database.close();
}
