import { and, eq, isNull } from "drizzle-orm";
import { ApiError } from "../api/errors";
import type { Database } from "../db/client";
import { athletes } from "../db/schema";

export async function requireAthlete(db: Database, authUserId: string) {
  const [athlete] = await db
    .select()
    .from(athletes)
    .where(and(eq(athletes.authUserId, authUserId), isNull(athletes.deletedAt)))
    .limit(1);
  if (!athlete)
    throw new ApiError(
      403,
      "ATHLETE_UNAVAILABLE",
      "The athlete account is unavailable.",
    );
  return athlete;
}
