// Run from any directory: bun contracts/fixtures/ai/validate.ts
import { createHash } from "node:crypto";
import { PlannedWorkoutInput } from "../../../server/src/plans/schemas";
const load = async (name: string) => Bun.file(new URL(name, import.meta.url)).json();
const run = PlannedWorkoutInput.parse(await load("mixed-run.json"));
PlannedWorkoutInput.parse(await load("rich-strength.json"));
if (run.discipline !== "running") throw new Error("Expected run fixture");
const ids = run.run.blocks.flatMap((block) =>
  Array.from({ length: block.repeatCount }, (_, iteration) =>
    block.steps.map((step) => {
      const input = `hybrd.run-step.v1|${block.id.toUpperCase()}|${step.id.toUpperCase()}|${iteration}`;
      const bytes = createHash("sha256").update(input).digest().subarray(0, 16);
      bytes[6] = (bytes[6]! & 15) | 0x50;
      bytes[8] = (bytes[8]! & 63) | 0x80;
      const hex = bytes.toString("hex");
      return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
    }),
  ).flat(),
);
if (JSON.stringify(ids) !== JSON.stringify(await load("mixed-run-execution-ids.json")))
  throw new Error("TypeScript and Swift executable identities differ");
console.log("PASS: canonical run/strength schemas and shared execution identities");
