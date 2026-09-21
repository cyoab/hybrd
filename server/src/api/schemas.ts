import { z } from "@hono/zod-openapi";

export const ErrorSchema = z
  .object({
    error: z.object({
      code: z.string(),
      message: z.string(),
      details: z.record(z.string(), z.unknown()).optional(),
      requestId: z.string().uuid(),
    }),
  })
  .openapi("ApiError");

export const errorResponse = {
  description: "Request failed. Use the stable error code for client behavior.",
  content: { "application/json": { schema: ErrorSchema } },
};
export const protectedErrors = {
  400: errorResponse,
  401: errorResponse,
  413: errorResponse,
  500: errorResponse,
};
export const security = [{ bearerAuth: [] }];

// Decimal strings preserve PostgreSQL bigint precision in TypeScript and Swift.
export const CursorSchema = z
  .string()
  .regex(/^(0|[1-9][0-9]*)$/)
  .max(19)
  .openapi("SyncCursor", { example: "0" });
export const AthleteSchema = z
  .object({
    id: z.string().uuid(),
    timezone: z.string(),
    locale: z.string(),
    distanceUnit: z.enum(["km", "mi"]),
    loadUnit: z.enum(["kg", "lb"]),
    weekStartsOn: z.number().int().min(1).max(7),
    revision: CursorSchema,
  })
  .openapi("Athlete");

export const EntitlementSchema = z
  .object({
    key: z.string(),
    status: z.enum(["active", "grace", "expired", "revoked"]),
    validUntil: z.string().datetime().nullable(),
  })
  .openapi("Entitlement");

export const TrainingPolicySchema = z
  .object({
    version: z.number().int().positive(),
    schemaVersion: z.number().int().positive(),
    checksum: z.string(),
    config: z.record(z.string(), z.unknown()),
    minimumAppVersion: z.string().nullable(),
  })
  .openapi("TrainingPolicy");

export const BootstrapSchema = z
  .object({
    athlete: AthleteSchema,
    device: z.object({ registered: z.boolean() }),
    sync: z.object({ available: z.boolean(), latestSequence: CursorSchema }),
    policy: z
      .object({ version: z.number().int(), checksum: z.string() })
      .nullable(),
    entitlements: z.array(EntitlementSchema),
  })
  .openapi("Bootstrap");

export const DeviceInputSchema = z
  .object({
    appVersion: z.string().min(1).max(64),
    osVersion: z.string().min(1).max(64).optional(),
    pushToken: z
      .string()
      .regex(/^[a-fA-F0-9]+$/)
      .min(32)
      .max(512)
      .nullable()
      .optional(),
    pushEnabled: z.boolean().default(false),
  })
  .strict()
  .refine((v) => !v.pushEnabled || Boolean(v.pushToken), {
    message: "A push token is required when push notifications are enabled.",
    path: ["pushToken"],
  })
  .openapi("DeviceRegistration");

export const DeviceSchema = z
  .object({ id: z.string().uuid(), registered: z.literal(true) })
  .openapi("RegisteredDevice");

export type Bootstrap = z.infer<typeof BootstrapSchema>;
export type TrainingPolicy = z.infer<typeof TrainingPolicySchema>;
export type Entitlement = z.infer<typeof EntitlementSchema>;
export type DeviceInput = z.infer<typeof DeviceInputSchema>;
