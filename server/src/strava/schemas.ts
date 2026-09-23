import { z } from "@hono/zod-openapi";
import { Id } from "../domain/schemas";

export const ConnectInput = z
  .object({ autoPublish: z.boolean().default(true) })
  .strict();
export const CompleteInput = z
  .object({
    state: z.string().min(32).max(128),
    code: z.string().min(1).max(2000),
    scope: z.string().max(1000),
  })
  .strict();
export const JobSchema = z.object({
  id: Id,
  kind: z.enum(["history", "publish", "revoke"]),
  workoutId: Id.nullable(),
  state: z.string(),
  remoteId: z.string().nullable(),
  errorCode: z.string().nullable(),
  updatedAt: z.iso.datetime(),
});
export const HistorySchema = z
  .object({
    source: z.literal("strava"),
    generatedAt: z.iso.datetime(),
    expiresAt: z.iso.datetime(),
    periodStart: z.iso.datetime(),
    periodEnd: z.iso.datetime(),
    activityCount: z.number().int(),
    historyComplete: z.boolean(),
    heartRateZones: z
      .object({
        custom: z.boolean(),
        ranges: z.array(
          z.object({ minBpm: z.number(), maxBpm: z.number().nullable() }),
        ),
      })
      .nullable(),
    running: z.array(
      z.object({
        days: z.number().int(),
        runs: z.number().int(),
        distanceM: z.number(),
        elapsedSeconds: z.number(),
        movingSeconds: z.number(),
        averageMovingPaceSecondsPerKm: z.number().nullable(),
        averageWeeklyDistanceM: z.number(),
        averageRunsPerWeek: z.number(),
      }),
    ),
    strengthSessions: z.number().int(),
    longestRunM: z.number().nullable(),
    observedBestEfforts: z.array(
      z.object({
        name: z.string(),
        distanceM: z.number(),
        elapsedSeconds: z.number().int(),
        activityId: z.string(),
        performedAt: z.iso.datetime(),
      }),
    ),
    bestEffortCoverage: z.object({
      scope: z.literal("sampled_runs_within_period"),
      inspectedRuns: z.number().int(),
      totalRuns: z.number().int(),
      allTimePersonalBests: z.literal(false),
    }),
    missing: z.array(z.string()),
    requiresReview: z.literal(true),
  })
  .openapi("StravaHistoryPreview");
export const StatusSchema = z
  .object({
    available: z.boolean(),
    status: z.enum([
      "not_connected",
      "connected",
      "reauthentication_required",
      "disconnecting",
      "disconnected",
    ]),
    remoteAthleteId: z.string().nullable(),
    autoPublish: z.boolean(),
    scopes: z.array(z.string()),
    history: HistorySchema.nullable(),
    jobs: z.array(JobSchema),
  })
  .openapi("StravaConnectionStatus");
export const WebhookInput = z.object({
  object_type: z.enum(["activity", "athlete"]),
  aspect_type: z.enum(["create", "update", "delete"]),
  object_id: z
    .union([z.number().int().safe(), z.string().regex(/^\d+$/)])
    .transform(String),
  owner_id: z
    .union([z.number().int().safe(), z.string().regex(/^\d+$/)])
    .transform(String),
  subscription_id: z
    .union([z.number().int().safe(), z.string().regex(/^\d+$/)])
    .transform(String),
  event_time: z.number().int().positive(),
  updates: z.record(z.string(), z.union([z.string(), z.boolean()])).default({}),
});
