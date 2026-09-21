import { z } from "@hono/zod-openapi";
import { CursorSchema } from "../api/schemas";

// Draft envelope only; payloads become discriminated, entity-specific schemas
// as each transactional mutation handler is implemented.
export const SyncMutationSchema = z
  .object({
    id: z.string().uuid(),
    entityType: z.string().min(1).max(64),
    entityId: z.string().uuid(),
    operation: z.enum(["create", "update", "delete", "activate_plan"]),
    baseRevision: CursorSchema.nullable(),
    payload: z.record(z.string(), z.unknown()),
  })
  .strict()
  .openapi("SyncMutation");

export const SyncPushSchema = z
  .object({
    deviceId: z.string().uuid(),
    mutations: z.array(SyncMutationSchema).min(1).max(100),
  })
  .strict()
  .openapi("SyncPush");

export const SyncPullQuerySchema = z
  .object({
    cursor: CursorSchema.default("0"),
    limit: z.coerce.number().int().min(1).max(500).default(100),
  })
  .openapi("SyncPullQuery");
