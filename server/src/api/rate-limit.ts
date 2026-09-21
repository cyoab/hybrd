import { ApiError } from "./errors";
// Deliberately process-local for the documented single-instance MVP deployment.
// Provider quotas are separate and persisted in PostgreSQL.
export function rateLimiter(
  limit: number,
  windowMs = 60000,
  clock: () => number = Date.now,
) {
  const buckets = new Map<string, { count: number; expires: number }>();
  let nextCleanup = 0;
  return (key: string) => {
    const now = clock();
    if (now >= nextCleanup) {
      for (const [id, bucket] of buckets)
        if (bucket.expires <= now) buckets.delete(id);
      nextCleanup = now + windowMs;
    }
    const current = buckets.get(key);
    if (current && current.expires > now) {
      if (current.count >= limit)
        throw new ApiError(
          429,
          "RATE_LIMITED",
          "Too many requests. Retry after one minute.",
        );
      current.count++;
    } else {
      if (buckets.size >= 10000)
        throw new ApiError(
          429,
          "RATE_LIMITED",
          "The request limit is temporarily reached.",
        );
      buckets.set(key, { count: 1, expires: now + windowMs });
    }
  };
}
