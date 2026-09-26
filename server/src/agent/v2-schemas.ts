import { z } from "@hono/zod-openapi";
import { CursorSchema } from "../api/schemas";
import { Day, Id } from "../domain/schemas";
import {
  exercise,
  type PlannedWorkoutInput,
  set,
  step,
} from "../plans/schemas";
import { AgentRun, AgentRunInput, Citation, MemoryInput } from "./schemas";

export const DeviceManifest = z
  .object({
    deviceId: Id,
    surface: z.enum(["phone", "watch"]),
    pairedDeviceId: Id.nullable(),
    appBuild: z.string().min(1).max(80),
    executableVersion: z.literal(2),
    prescriptionSchemaVersion: z.literal(1),
    maxExpandedSteps: z.number().int().min(1).max(2000),
    maxResultSegments: z.number().int().min(1).max(500),
    completion: z
      .array(z.enum(["duration", "distance", "manual"]))
      .min(1)
      .max(3),
    richStrength: z.boolean(),
    deviceActions: z
      .array(z.enum(["start", "pause", "resume", "lap", "finish"]))
      .max(5),
  })
  .strict()
  .openapi("AgentDeviceManifest");
export const MutationScope = z
  .object({
    contextToken: z.string().regex(/^[a-f0-9]{64}$/),
    trainingBlockId: Id.nullable(),
    expectedActivePlanVersionId: Id.nullable(),
    expectedProfileRevision: CursorSchema,
    outboxDrained: z.literal(true),
    protectedLogicalWorkoutIds: z.array(Id).max(300),
    mode: z.enum(["draft", "apply"]),
    startDate: Day,
    endDate: Day,
    operations: z
      .array(
        z.enum([
          "move",
          "replace_exercise",
          "replace_workout",
          "remove",
          "add",
        ]),
      )
      .max(5),
    allowRecurringPreference: z.boolean(),
  })
  .strict()
  .refine(
    (v) =>
      v.startDate <= v.endDate &&
      Date.parse(v.endDate) - Date.parse(v.startDate) <= 112 * 86400000,
    "Use an ordered horizon of at most 16 weeks",
  )
  .openapi("AgentMutationScope");
export const NativeScope = z
  .object({
    deviceId: Id,
    action: z.enum(["start", "pause", "resume", "lap", "finish"]),
    recordingId: Id,
    plannedWorkoutId: Id.nullable(),
    expectedLocalState: z.enum(["idle", "recording", "paused"]),
  })
  .strict()
  .openapi("AgentNativeScope");
export const AgentRunInputV2 = z
  .object({
    ...AgentRunInput.shape,
    schemaVersion: z.literal(2),
    task: z.enum([
      "chat",
      "analyze_workout",
      "create_plan",
      "modify_plan",
      "device_action",
    ]),
    mutation: MutationScope.nullable().default(null),
    native: NativeScope.nullable().default(null),
  })
  .strict()
  .superRefine((v, ctx) => {
    const write = v.task === "create_plan" || v.task === "modify_plan";
    if (
      write !== Boolean(v.mutation) ||
      (v.task === "device_action") !== Boolean(v.native)
    )
      ctx.addIssue({
        code: "custom",
        message: "Provide only the scope matching this task",
      });
    if (
      (v.task === "analyze_workout") !==
        Boolean(v.workoutResultId && v.expectedWorkoutRevision) ||
      (v.task !== "analyze_workout" &&
        (v.workoutResultId || v.expectedWorkoutRevision))
    )
      ctx.addIssue({
        code: "custom",
        message: "Analysis requires an exact result revision",
      });
    if (
      v.task === "create_plan" &&
      (v.mutation?.trainingBlockId || v.mutation?.expectedActivePlanVersionId)
    )
      ctx.addIssue({
        code: "custom",
        message:
          "Creation uses a new block; modify an existing block explicitly",
      });
    if (
      v.task === "modify_plan" &&
      (!v.mutation?.trainingBlockId || !v.mutation.expectedActivePlanVersionId)
    )
      ctx.addIssue({
        code: "custom",
        message: "Modification requires an active block and plan",
      });
  })
  .openapi("AgentRunInputV2");
export const AnyRunInput = z.union([AgentRunInput, AgentRunInputV2]);
export type RunInputV2 = z.infer<typeof AgentRunInputV2>;
export type AnyInput = z.infer<typeof AnyRunInput>;
const StepTemplate = z
  .object(step.shape)
  .omit({ id: true, sequence: true })
  .strict();
const SetTemplate = z
  .object(set.shape)
  .omit({ id: true, setNumber: true })
  .strict();
const ExerciseTemplate = z
  .object(exercise.shape)
  .omit({ id: true, sequence: true, sets: true, supersetGroupId: true })
  .extend({
    supersetKey: z.string().min(1).max(40).nullable(),
    sets: z.array(SetTemplate).min(1).max(20),
  })
  .strict();
const common = {
  key: z.string().min(1).max(40),
  title: z.string().min(1).max(200),
  workoutType: z.string().min(1).max(64),
  purpose: z.string().max(4000).nullable(),
  priority: z.enum(["key", "supporting", "optional"]),
  estimatedDurationS: z.number().int().positive().max(21600),
  instructions: z.string().max(4000).nullable(),
};
export const WorkoutTemplate = z
  .discriminatedUnion("discipline", [
    z
      .object({
        ...common,
        discipline: z.literal("running"),
        run: z
          .object({
            primaryTargetType: z.enum([
              "pace",
              "heart_rate",
              "rpe",
              "mixed",
              "open",
            ]),
            notes: z.string().max(4000).nullable(),
            blocks: z
              .array(
                z
                  .object({
                    repeatCount: z.number().int().min(1).max(100),
                    label: z.string().max(200).nullable(),
                    steps: z.array(StepTemplate).min(1).max(50),
                  })
                  .strict(),
              )
              .min(1)
              .max(30),
          })
          .strict(),
      })
      .strict(),
    z
      .object({
        ...common,
        discipline: z.literal("strength"),
        strength: z
          .object({
            sessionFocus: z.string().min(1).max(64),
            notes: z.string().max(4000).nullable(),
            exercises: z.array(ExerciseTemplate).min(1).max(30),
          })
          .strict(),
      })
      .strict(),
  ])
  .openapi("AgentWorkoutTemplate");
export const Blueprint = z
  .object({
    schemaVersion: z.literal(1),
    name: z.string().min(1).max(200),
    phase: z.enum(["build", "maintain", "deload", "taper", "recovery"]),
    rationale: z.string().min(1).max(4000),
    evidenceIds: z.array(z.string().min(1).max(80)).min(1).max(8),
    templates: z.array(WorkoutTemplate).min(1).max(32),
    sessions: z
      .array(
        z
          .object({ templateKey: z.string().min(1).max(40), date: Day })
          .strict(),
      )
      .min(1)
      .max(300),
  })
  .strict()
  .openapi("AgentPlanBlueprint");
export type Template = z.infer<typeof WorkoutTemplate>;
export type Workout = z.infer<typeof PlannedWorkoutInput>;
export const PlanEdit = z
  .object({
    rationale: z.string().min(1).max(4000),
    evidenceIds: z.array(z.string().max(80)).min(1).max(8),
    operations: z
      .array(
        z.discriminatedUnion("kind", [
          z
            .object({
              kind: z.literal("move"),
              logicalWorkoutId: Id,
              date: Day,
            })
            .strict(),
          z
            .object({
              kind: z.literal("replace_exercise"),
              logicalWorkoutId: Id,
              fromExerciseId: Id,
              toExerciseId: Id,
            })
            .strict(),
          z
            .object({
              kind: z.literal("replace_workout"),
              logicalWorkoutId: Id,
              template: WorkoutTemplate,
            })
            .strict(),
          z
            .object({ kind: z.literal("remove"), logicalWorkoutId: Id })
            .strict(),
          z
            .object({
              kind: z.literal("add"),
              date: Day,
              template: WorkoutTemplate,
            })
            .strict(),
        ]),
      )
      .min(1)
      .max(300),
    recurringPreference: z
      .object({ fromExerciseId: Id, toExerciseId: Id })
      .strict()
      .nullable(),
  })
  .strict()
  .openapi("AgentPlanEdit");
export const ActionReceipt = z
  .object({
    id: Id,
    runId: Id,
    lifecycle: z.enum(["draft", "applied", "undone"]),
    trainingBlockId: Id,
    planVersionId: Id,
    planRevision: CursorSchema,
    previousPlanVersionId: Id.nullable(),
    policyVersionId: Id,
    validationVersion: z.literal("agent-plan-validator-1"),
    citations: z.array(Citation),
    changes: z.array(
      z.object({
        logicalWorkoutId: Id,
        kind: z.enum(["added", "removed", "moved", "prescription_changed"]),
        beforePlannedWorkoutId: Id.nullable(),
        afterPlannedWorkoutId: Id.nullable(),
      }),
    ),
    changedLogicalWorkoutIds: z.array(Id),
    rationale: z.string(),
    evidenceIds: z.array(z.string()),
    validationIssues: z.array(
      z.object({ code: z.string(), message: z.string() }),
    ),
    compatibility: z.object({
      executableVersion: z.literal(2),
      prescriptionSchemaVersion: z.literal(1),
    }),
    syncRequired: z.literal(true),
    undoAvailable: z.boolean(),
    undoExpiresAt: z.string().datetime(),
    undoneByPlanVersionId: Id.nullable(),
    createdAt: z.string().datetime(),
  })
  .openapi("AgentActionReceipt");
export const DeviceChallenge = z
  .object({
    id: Id,
    runId: Id,
    scope: NativeScope,
    digest: z.string(),
    claimToken: Id.nullable().default(null),
    status: z.enum([
      "pending",
      "claimed",
      "indeterminate",
      "executed",
      "rejected",
      "unavailable",
      "expired",
    ]),
    expiresAt: z.string().datetime(),
    result: z
      .object({
        localState: z.enum(["idle", "recording", "paused", "finished"]),
        reason: z.string().max(500).nullable(),
      })
      .nullable(),
  })
  .openapi("AgentDeviceChallenge");
export const AgentRunV2 = AgentRun.extend({
  schemaVersion: z.literal(2),
  task: AgentRunInputV2.shape.task,
  action: ActionReceipt.nullable(),
  deviceChallenge: DeviceChallenge.nullable(),
  learnedMemoryIds: z.array(Id),
}).openapi("AgentRunV2");
export const MemoryCandidate = MemoryInput.omit({ expectedRevision: true })
  .extend({
    sourceQuote: z.string().min(3).max(500),
    confidence: z.number().min(0.9).max(1),
  })
  .strict();
export const LearnedMemory = z
  .object({
    id: Id,
    revision: CursorSchema,
    category: MemoryInput.shape.category,
    content: z.string(),
    expiresAt: z.string().datetime().nullable(),
    source: z.enum(["athlete", "learned"]),
    sourceRunId: Id.nullable(),
    sourceMessageId: Id.nullable(),
    confidence: z.number().nullable(),
    sourceQuote: z.string().nullable(),
    createdAt: z.string().datetime(),
    updatedAt: z.string().datetime(),
  })
  .openapi("AgentMemoryV2");
export const MemorySettings = z
  .object({ enabled: z.boolean(), expectedRevision: CursorSchema })
  .strict()
  .openapi("AgentMemorySettingsInput");
export const UndoInput = z
  .object({
    expectedActivePlanVersionId: Id.nullable(),
    outboxDrained: z.literal(true),
    protectedLogicalWorkoutIds: z.array(Id).max(300),
    contextToken: z.string().regex(/^[a-f0-9]{64}$/),
    deviceId: Id,
  })
  .strict()
  .openapi("AgentUndoInput");
export const AnalysisPacket = z
  .object({
    schemaVersion: z.literal(1),
    algorithmVersion: z.string().min(1).max(80),
    deviceId: Id,
    resultId: Id,
    resultRevision: CursorSchema,
    plannedWorkoutId: Id.nullable(),
    recordingId: Id,
    source: z.enum(["iphone", "watch", "healthkit", "manual"]),
    startedAt: z.string().datetime(),
    endedAt: z.string().datetime(),
    elapsedDurationS: z.number().nonnegative().max(604800),
    activeDurationS: z.number().nonnegative().max(604800).nullable(),
    movingDurationS: z.number().nonnegative().max(604800).nullable(),
    consentVersion: z.literal(1),
    units: z.literal("seconds_meters_bpm"),
    coverage: z
      .object({
        heartRate: z.enum(["none", "summary_only", "partial", "complete"]),
        omissions: z.array(z.string().max(200)).max(20),
      })
      .strict(),
    heartRate: z
      .array(
        z
          .object({
            elapsedS: z.number().nonnegative(),
            bpm: z.number().min(20).max(250),
          })
          .strict(),
      )
      .max(1000),
    boundaries: z
      .array(
        z
          .object({
            series: z.enum([
              "prescription_interval",
              "automatic_split",
              "manual_lap",
            ]),
            blockId: Id.nullable(),
            stepId: Id.nullable(),
            repeatIteration: z.number().int().min(0).max(99).nullable(),
            activeSeconds: z.number().nonnegative(),
            cumulativeMeters: z.number().nonnegative(),
            reason: z.enum([
              "targetReached",
              "manualAdvance",
              "workoutFinished",
            ]),
          })
          .strict(),
      )
      .max(2000),
    checksum: z.string().regex(/^[a-f0-9]{64}$/),
  })
  .strict()
  .openapi("AgentAnalysisPacket");
