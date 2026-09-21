import { z } from "@hono/zod-openapi";
import { hash } from "../db/store";
export const PolicyConfigSchema = z
  .object({
    features: z
      .object({
        sync: z.boolean(),
        remoteDecisions: z.boolean(),
        remoteCoach: z.boolean(),
        billing: z.boolean(),
      })
      .strict(),
    interference: z
      .object({
        lowerBeforeKeyRun: z
          .object({
            warningHours: z.number().min(0).max(168),
            severeHours: z.number().min(0).max(168),
          })
          .strict()
          .refine((v) => v.severeHours <= v.warningHours),
      })
      .strict(),
    running: z
      .object({
        defaultProgression: z
          .object({ maxWeeklyIncrease: z.number().min(0).max(0.25) })
          .strict(),
      })
      .strict(),
    strength: z
      .object({
        maxLoadIncreaseFraction: z.number().min(0).max(0.25),
        maxSetsPerExercise: z.number().int().min(1).max(20),
      })
      .strict(),
    intelligence: z
      .object({
        jevConfidence: z
          .object({
            auto: z.number().min(0).max(1),
            review: z.number().min(0).max(1),
          })
          .strict()
          .refine((v) => v.review <= v.auto),
        proposalExpiryHours: z.number().int().min(1).max(168),
      })
      .strict(),
  })
  .strict()
  .openapi("PolicyConfig");
// Development values are architecture examples, not a reviewed training prescription.
export const developmentPolicy = PolicyConfigSchema.parse({
  features: {
    sync: true,
    remoteDecisions: true,
    remoteCoach: true,
    billing: true,
  },
  interference: { lowerBeforeKeyRun: { warningHours: 36, severeHours: 18 } },
  running: { defaultProgression: { maxWeeklyIncrease: 0.1 } },
  strength: { maxLoadIncreaseFraction: 0.05, maxSetsPerExercise: 6 },
  intelligence: {
    jevConfidence: { auto: 0.9, review: 0.7 },
    proposalExpiryHours: 24,
  },
});
export function policyChecksum(config: Record<string, unknown>) {
  return `sha256:${hash(config)}`;
}
