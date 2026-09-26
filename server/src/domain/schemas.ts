import { z } from "@hono/zod-openapi";

export const Id = z.string().uuid();
export const Revision = z
  .string()
  .regex(/^(0|[1-9][0-9]*)$/)
  .refine(
    (v) => BigInt(v) <= 9223372036854775807n,
    "Outside PostgreSQL bigint range",
  );
export const Day = z.iso.date();
export const Instant = z.iso.datetime({ offset: true });
export const Zone = z
  .string()
  .max(100)
  .refine((v) => {
    try {
      new Intl.DateTimeFormat("en", { timeZone: v });
      return true;
    } catch {
      return false;
    }
  }, "Expected an IANA time zone");
export const Notes = z.string().max(4000).nullable().default(null);
export const Effort = z.number().min(0).max(10).multipleOf(0.1);
export const Load = z.number().min(0).max(99999).multipleOf(0.001);
export const Count = z.number().int().min(0).max(32767);
export const Seconds = z.number().int().min(0).max(604800);
export const Distance = z.number().int().min(0).max(1000000);
export const Features = z
  .record(
    z.string().min(1).max(64),
    z.union([z.number().finite(), z.boolean(), z.string().max(200), z.null()]),
  )
  .refine((v) => Object.keys(v).length <= 64, "At most 64 compact features");
export function uniqueBy<T>(items: T[], key: (item: T) => unknown) {
  return new Set(items.map(key)).size === items.length;
}
export function orderedRange(
  min: number | null | undefined,
  max: number | null | undefined,
) {
  return min == null || max == null || min <= max;
}
export const optionalId = Id.nullable().default(null);
export const optionalInstant = Instant.nullable().default(null);
