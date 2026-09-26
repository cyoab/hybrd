import { z } from "@hono/zod-openapi";
import { CursorSchema } from "../api/schemas";
import { PlannedWorkoutInput } from "../plans/schemas";
import { DeviceManifest } from "./v2-schemas";
export const AgentCapabilitiesV2 = z
  .object({
    schemaVersion: z.literal(2),
    supportedSchemaVersions: z.array(z.union([z.literal(1), z.literal(2)])),
    enabled: z.boolean(),
    configured: z.boolean(),
    tasks: z.object({
      chat: z.boolean(),
      analyze_workout: z.boolean(),
      create_plan: z.boolean(),
      modify_plan: z.boolean(),
      device_action: z.boolean(),
    }),
    transport: z.literal("sse"),
    memory: z.literal("opt_in_learning"),
    requiresConsent: z.literal(true),
    requiredEntitlement: z.string(),
    maxGenerativeCalls: z.number().int(),
    eventRetentionDays: z.literal(7),
    executableVersion: z.literal(2),
    prescriptionSchemaVersion: z.literal(1),
  })
  .openapi("AgentCapabilitiesV2");
export const PlanningContextView = z
  .object({
    contextToken: z.string(),
    profileRevision: CursorSchema,
    timezone: z.string(),
    trainingDayBoundary: z.string(),
    blocks: z.array(
      z.object({
        id: z.string().uuid(),
        activePlanVersionId: z.string().uuid().nullable(),
        revision: CursorSchema,
        startDate: z.string(),
        endDate: z.string(),
      }),
    ),
    exerciseRules: z.array(
      z.object({
        athleteId: z.string().uuid(),
        fromExerciseId: z.string().uuid(),
        toExerciseId: z.string().uuid(),
        actionId: z.string().uuid(),
        revision: CursorSchema,
      }),
    ),
    workouts: z.array(PlannedWorkoutInput),
  })
  .openapi("AgentPlanningContext");
export const ClaimInput = z
  .object({
    deviceId: z.string().uuid(),
    digest: z.string().regex(/^[a-f0-9]{64}$/),
    recordingId: z.string().uuid(),
  })
  .strict()
  .openapi("AgentDeviceClaim");
export const AckInput = z
  .object({
    deviceId: z.string().uuid(),
    digest: z.string().regex(/^[a-f0-9]{64}$/),
    claimToken: z.string().uuid(),
    recordingId: z.string().uuid(),
    status: z.enum(["executed", "rejected", "unavailable"]),
    localState: z.enum(["idle", "recording", "paused", "finished"]),
    reason: z.string().max(500).nullable(),
  })
  .strict()
  .openapi("AgentDeviceAcknowledgment");
export const ManifestReceipt = z
  .object({ manifest: DeviceManifest, expiresAt: z.string().datetime() })
  .openapi("AgentManifestReceipt");
