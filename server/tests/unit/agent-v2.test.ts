import { expect, test } from "bun:test";
import { z } from "zod";
import { cloneWorkout, expandTemplate } from "../../src/agent/planning";
import { strictToolSchema, tool } from "../../src/agent/provider";
import {
  AgentRunInputV2,
  Blueprint,
  DeviceManifest,
  WorkoutTemplate,
} from "../../src/agent/v2-schemas";
import { hash } from "../../src/db/store";
import { PlannedWorkoutInput } from "../../src/plans/schemas";
import { semantic } from "../../src/plans/service";

const uuid = () => crypto.randomUUID();
const template = () =>
  WorkoutTemplate.parse({
    key: "intervals",
    discipline: "running",
    title: "Repeats",
    workoutType: "intervals",
    purpose: null,
    priority: "key",
    estimatedDurationS: 2400,
    instructions: null,
    run: {
      primaryTargetType: "mixed",
      notes: null,
      blocks: [
        {
          label: "Repeats",
          repeatCount: 4,
          steps: [
            {
              stepKind: "work",
              durationS: 120,
              paceMinSPerKm: 255.5,
              paceMaxSPerKm: 270.25,
              hrMinBpm: 150,
              hrMaxBpm: 170,
              rpeMin: 6.5,
              rpeMax: 7.5,
            },
            { stepKind: "recovery", distanceM: 200, rpeMin: 2, rpeMax: 3 },
          ],
        },
      ],
    },
  });
test("blueprint compiler retains fractional targets, sequence and repeated-step identity while allocating unique physical IDs", () => {
  const a = expandTemplate(template(), "2026-11-01", "America/New_York"),
    b = expandTemplate(template(), "2026-11-08", "America/New_York");
  expect(a.id).not.toBe(b.id);
  expect(a.logicalWorkoutId).not.toBe(b.logicalWorkoutId);
  expect(a.scheduledStartAt).toBeNull();
  if (a.discipline !== "running" || b.discipline !== "running")
    throw new Error("wrong discipline");
  expect(a.run.blocks[0]?.repeatCount).toBe(4);
  expect(a.run.blocks[0]?.steps[0]?.paceMinSPerKm).toBe(255.5);
  expect(a.run.blocks[0]?.steps[1]?.sequence).toBe(1);
  expect(a.run.blocks[0]?.id).not.toBe(b.run.blocks[0]?.id);
  const clone = cloneWorkout(a);
  expect(clone.logicalWorkoutId).toBe(a.logicalWorkoutId);
  expect(clone.id).not.toBe(a.id);
  expect(hash(semantic(clone))).toBe(hash(semantic(a)));
  expect(PlannedWorkoutInput.safeParse(clone).success).toBe(true);
});
test("strength compilation retains rich set kinds, decimals, supersets, rest and substitutions", () => {
  const t = WorkoutTemplate.parse({
    key: "strength",
    discipline: "strength",
    title: "Press",
    workoutType: "upper",
    purpose: null,
    priority: "key",
    estimatedDurationS: 1800,
    instructions: null,
    strength: {
      sessionFocus: "upper",
      notes: null,
      exercises: [
        {
          exerciseId: uuid(),
          supersetKey: "A",
          substitutionAllowed: true,
          notes: null,
          sets: [
            {
              setKind: "backoff",
              repsMin: 6,
              repsMax: 8,
              loadKg: 12.375,
              rpeMin: 6.5,
              rpeMax: 7,
              rirMin: 3,
              rirMax: 4,
              restS: 90,
              notes: null,
            },
          ],
          substitutions: [
            {
              exerciseId: uuid(),
              priority: 0,
              rationale: "Available equipment",
            },
          ],
        },
      ],
    },
  });
  const w = expandTemplate(t, "2026-10-01", "America/Monterrey");
  if (w.discipline !== "strength") throw new Error("wrong discipline");
  const e = w.strength.exercises[0]!;
  expect(e.supersetGroupId).not.toBeNull();
  expect(e.sets[0]?.loadKg).toBe(12.375);
  expect(e.sets[0]?.setKind).toBe("backoff");
  expect(e.substitutions).toHaveLength(1);
});
test("v2 requests cannot smuggle task scopes or omit exact analysis revisions", () => {
  const base = {
    schemaVersion: 2,
    deviceId: uuid(),
    task: "chat",
    message: "Training",
  };
  expect(AgentRunInputV2.safeParse(base).success).toBe(true);
  expect(
    AgentRunInputV2.safeParse({ ...base, task: "create_plan" }).success,
  ).toBe(false);
  expect(
    AgentRunInputV2.safeParse({
      ...base,
      task: "analyze_workout",
      workoutResultId: uuid(),
    }).success,
  ).toBe(false);
  expect(
    AgentRunInputV2.safeParse({ ...base, tools: ["execute_sql"] }).success,
  ).toBe(false);
  expect(
    DeviceManifest.safeParse({
      deviceId: uuid(),
      surface: "watch",
      pairedDeviceId: null,
      appBuild: "2",
      executableVersion: 1,
      prescriptionSchemaVersion: 1,
      maxExpandedSteps: 2000,
      maxResultSegments: 500,
      completion: ["duration"],
      richStrength: false,
      deviceActions: [],
    }).success,
  ).toBe(false);
});
test("strict provider schemas require every nested property and express missing values as null", () => {
  const schema = tool("stage_plan", "test", Blueprint).function.parameters;
  const visit = (value: unknown) => {
    if (!value || typeof value !== "object") return;
    if (Array.isArray(value)) {
      value.forEach(visit);
      return;
    }
    const r = value as Record<string, unknown>;
    if (r.type === "object" && r.properties) {
      expect(r.additionalProperties).toBe(false);
      expect(new Set(r.required as string[])).toEqual(
        new Set(Object.keys(r.properties as object)),
      );
    }
    Object.values(r).forEach(visit);
  };
  visit(schema);
  const result = strictToolSchema(
    z.toJSONSchema(z.object({ target: z.number().nullable().default(null) }), {
      io: "input",
    }),
  );
  expect(result.required).toEqual(["target"]);
});

test("published v2 examples decode with exact negotiated schemas and packet checksums", async () => {
  const { ActionReceipt, AgentRunV2, AnalysisPacket, DeviceChallenge } =
    await import("../../src/agent/v2-schemas");
  const read = async (name: string) =>
    Bun.file(
      new URL(`../../../contracts/examples/${name}.json`, import.meta.url),
    ).json();
  for (const name of ["agent-v2-create", "agent-v2-edit"])
    AgentRunInputV2.parse(await read(name));
  for (const name of ["agent-v2-run-draft", "agent-v2-run-applied"])
    AgentRunV2.parse(await read(name));
  for (const name of [
    "agent-v2-device-challenge",
    "agent-v2-device-claimed",
    "agent-v2-device-executed",
    "agent-v2-device-expired",
  ])
    DeviceChallenge.parse(await read(name));
  for (const name of ["agent-v2-device-manifest", "agent-v2-watch-manifest"])
    DeviceManifest.parse(await read(name));
  ActionReceipt.parse(await read("agent-v2-action-undone"));
  Blueprint.parse(await read("agent-v2-blueprint"));
  const { checksum, ...p } = AnalysisPacket.parse(
    await read("agent-v2-analysis-packet"),
  );
  expect(checksum).toBe(hash(p));
});

test("relative training days respect timezone, DST and the athlete's day boundary", async () => {
  const { trainingToday } = await import("../../src/agent/planning");
  expect(
    trainingToday(
      "America/New_York",
      "04:00:00",
      new Date("2026-11-01T06:30:00Z"),
    ),
  ).toBe("2026-10-31");
  expect(
    trainingToday(
      "America/New_York",
      "04:00:00",
      new Date("2026-11-01T09:00:00Z"),
    ),
  ).toBe("2026-11-01");
  expect(
    trainingToday("America/Monterrey", null, new Date("2026-10-01T02:00:00Z")),
  ).toBe("2026-09-30");
});
