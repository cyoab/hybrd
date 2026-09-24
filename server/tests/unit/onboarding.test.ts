import { expect, test } from "bun:test";
import { AthleteDetails, HeartRateZones } from "../../src/athlete/details";
import { Draft } from "../../src/onboarding/schemas";

test("five-zone contract preserves fractional/open boundaries and rejects gaps/overlaps/early unbounded ranges", () => {
  const ranges = [
    { minBpm: 0, maxBpm: 120.5 },
    { minBpm: 120.5, maxBpm: 140.5 },
    { minBpm: 140.5, maxBpm: 160.5 },
    { minBpm: 160.5, maxBpm: 180.5 },
    { minBpm: 180.5, maxBpm: null },
  ];
  const input = {
    schemaVersion: 1 as const,
    configuration: "system" as const,
    ranges,
  };
  expect(HeartRateZones.parse(input)).toEqual(input);
  for (const patch of [
    { minBpm: 121, maxBpm: 140.5 },
    { minBpm: 120, maxBpm: 140.5 },
    { minBpm: 120.5, maxBpm: null },
  ])
    expect(
      HeartRateZones.safeParse({
        ...input,
        ranges: [ranges[0], patch, ...ranges.slice(2)],
      }).success,
    ).toBe(false);
  expect(
    HeartRateZones.safeParse({ ...input, ranges: ranges.slice(0, 4) }).success,
  ).toBe(false);
});
test("canonical body ranges and age are strict, and baseline zero differs from unknown", () => {
  const d = {
    preferredName: " Sam ",
    heightUnit: "cm",
    dateOfBirth: null,
    age: null,
    weightKg: null,
    heightCm: null,
    heartRateZones: null,
    runningRecords: [],
    strengthRecords: [],
  };
  expect(AthleteDetails.parse(d).preferredName).toBe("Sam");
  for (const change of [
    { weightKg: 19 },
    { weightKg: 401 },
    { heightCm: 79 },
    { heightCm: 251 },
    { age: { years: 1.5, asOf: "2026-09-01" } },
    { age: { years: 30, asOf: "2026-09-01" }, dateOfBirth: "1996-01-01" },
  ])
    expect(AthleteDetails.safeParse({ ...d, ...change }).success).toBe(false);
  const field = Draft.shape.weeklyDistanceM;
  for (const value of [0, 0.1, 70123.456789, 250000, null])
    expect(field.parse(value)).toBe(value);
  for (const value of [-1, 250001, "70000"])
    expect(field.safeParse(value).success).toBe(false);
});

test("published onboarding request example remains a valid wire contract", async () => {
  const { SaveDraftInput } = await import("../../src/onboarding/schemas");
  const input = await Bun.file(
    new URL(
      "../../../contracts/examples/onboarding-draft.json",
      import.meta.url,
    ),
  ).json();
  expect(SaveDraftInput.safeParse(input).success).toBe(true);
});

test("UTC imported windows remain usable when the athlete calendar is still the previous day", async () => {
  const { Draft } = await import("../../src/onboarding/schemas"),
    { validateComplete } = await import("../../src/onboarding/service");
  const input = await Bun.file(
    new URL(
      "../../../contracts/examples/onboarding-draft.json",
      import.meta.url,
    ),
  ).json();
  const d = Draft.parse(input.draft);
  d.profile = { ...input.draft.profile, timezone: "Pacific/Honolulu" };
  d.baselinePeriod = { start: "2026-08-27", end: "2026-09-24" };
  expect(() =>
    validateComplete(d, new Date("2026-09-24T01:00:00Z")),
  ).not.toThrow();
  d.baselinePeriod.end = "2026-09-25";
  expect(() => validateComplete(d, new Date("2026-09-24T01:00:00Z"))).toThrow();
});
