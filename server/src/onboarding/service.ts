import type postgres from "postgres";
import { ZodError, type z } from "zod";
import { ApiError } from "../api/errors";
import { catalogVersion } from "../catalog/data";
import { legacyOnboardingPolicy, OnboardingPolicy } from "../config/policy";
import { hash, type Row, type Tx, withAthlete } from "../db/store";
import { applyMutation } from "../sync/mutations";
import { SyncMutationSchema } from "../sync/schemas";
import { requireDevice } from "../sync/service";
import { referenceOnlyDraft, resolveImports } from "./imports";
import {
  CompleteInput,
  Draft,
  type DraftData,
  DraftSaved,
  OnboardingState,
  Receipt,
  SaveDraftInput,
} from "./schemas";

function invalid(
  fields: string[],
  message = "Review the required onboarding answers.",
): never {
  throw new ApiError(422, "ONBOARDING_VALIDATION_FAILED", message, { fields });
}
export function validateComplete(d: DraftData, now: Date) {
  const required: (keyof DraftData)[] = [
    "profile",
    "runningGoal",
    "strengthGoal",
    "priority",
    "runningLevel",
    "strengthLevel",
    "weeklyDistanceM",
    "currentStrengthSessionsPerWeek",
    "baselinePeriod",
    "availableDays",
    "desiredStrengthSessionsPerWeek",
    "sessionMinutes",
    "equipmentIds",
    "focusMuscleIds",
    "readiness",
  ];
  const missing = required.filter((k) => d[k] === null).map(String);
  if (!d.details.preferredName) missing.push("details.preferredName");
  if (!d.equipmentConfirmed) missing.push("equipmentConfirmed");
  if (missing.length) invalid(missing);
  const days = d.availableDays ?? [];
  if (days.length < 2 || (d.desiredStrengthSessionsPerWeek ?? 0) > days.length)
    invalid(["availableDays", "desiredStrengthSessionsPerWeek"]);
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: d.profile?.timezone ?? "UTC",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
  if (d.raceDate && (d.runningGoal === "fitness" || d.raceDate < today))
    invalid(["raceDate"]);
  if (d.details.dateOfBirth && d.details.dateOfBirth > today)
    invalid(["details.dateOfBirth"]);
  if (d.details.age && d.details.age.asOf > today)
    invalid(["details.age.asOf"]);
  // Provider windows use UTC while manual/race dates use the athlete calendar.
  const latestObservationDay =
    [today, now.toISOString().slice(0, 10)].sort().at(-1) ?? today;
  if (d.baselinePeriod && d.baselinePeriod.end > latestObservationDay)
    invalid(["baselinePeriod"]);
  for (const record of [
    ...d.details.runningRecords,
    ...d.details.strengthRecords,
  ])
    if (record.performedOn && record.performedOn > today)
      invalid(["details.runningRecords", "details.strengthRecords"]);
}
async function replay(
  sql: Tx,
  owner: string,
  route: string,
  key: string,
  input: unknown,
) {
  const [row] =
    await sql`select * from onboarding_requests where athlete_id=${owner} and route=${route} and key=${key}`;
  if (row && row.fingerprint !== hash(input))
    throw new ApiError(
      409,
      "IDEMPOTENCY_KEY_REUSED",
      "Use a new key for different request content.",
    );
  return row?.outcome;
}
async function remember(
  sql: Tx,
  owner: string,
  route: string,
  key: string,
  input: unknown,
  outcome: unknown,
) {
  await sql`insert into onboarding_requests (athlete_id,route,key,fingerprint,outcome) values (${owner},${route},${key},${hash(input)},${sql.json(JSON.parse(JSON.stringify(outcome)))})`;
}
export async function readOnboarding(sql: Tx, athlete: Row) {
  const [row] =
    await sql`select * from onboarding_states where athlete_id=${String(athlete.id)}`;
  if (!row)
    return OnboardingState.parse({
      schemaVersion: 1,
      status: "not_started",
      draft: null,
      draftRevision: null,
      step: null,
      completion: null,
      reviewIssues: [],
    });
  if (row.completion)
    return OnboardingState.parse({
      schemaVersion: 1,
      status: "completed",
      draft: null,
      draftRevision: String(row.revision),
      step: "membership",
      completion: row.completion,
      reviewIssues: [],
    });
  const resolved = await resolveImports(
    sql,
    String(athlete.id),
    Draft.parse(row.draft),
    "hydrate",
    true,
  );
  return OnboardingState.parse({
    schemaVersion: 1,
    status: "draft",
    draft: resolved.draft,
    draftRevision: String(row.revision),
    step: row.step,
    completion: null,
    reviewIssues: resolved.issues,
  });
}
export function onboardingServices(client: postgres.Sql) {
  return {
    get: (userId: string) => withAthlete(client, userId, readOnboarding),
    save: (
      userId: string,
      key: string,
      request: z.infer<typeof SaveDraftInput>,
    ) =>
      withAthlete(client, userId, async (sql, athlete) => {
        const input = SaveDraftInput.parse(request),
          owner = String(athlete.id);
        const previous = await replay(sql, owner, "draft", key, input);
        if (previous) return DraftSaved.parse(previous);
        const [row] =
          await sql`select * from onboarding_states where athlete_id=${owner}`;
        if (row?.completion)
          throw new ApiError(
            409,
            "ONBOARDING_ALREADY_COMPLETED",
            "Restore the completion receipt and use explicit profile edits.",
          );
        if ((row ? String(row.revision) : null) !== input.baseRevision)
          throw new ApiError(
            409,
            "ONBOARDING_REVISION_CONFLICT",
            "Reload the saved draft before merging your answers.",
            { fields: ["baseRevision"] },
          );
        await resolveImports(sql, owner, input.draft, "validate");
        const revision = String(row ? BigInt(String(row.revision)) + 1n : 1n);
        const stored = referenceOnlyDraft(input.draft);
        await sql`insert into onboarding_states (athlete_id,draft,revision,step,athlete_revision) values (${owner},${sql.json(stored)},${revision},${input.step},${String(athlete.revision)}) on conflict(athlete_id) do update set draft=excluded.draft,revision=excluded.revision,step=excluded.step,athlete_revision=excluded.athlete_revision,updated_at=now()`;
        const outcome = { draftRevision: revision };
        await remember(sql, owner, "draft", key, input, outcome);
        return outcome;
      }),
    complete: (
      userId: string,
      key: string,
      request: z.infer<typeof CompleteInput>,
    ) =>
      withAthlete(client, userId, async (sql, athlete) => {
        const input = CompleteInput.parse(request),
          owner = String(athlete.id);
        const previous = await replay(sql, owner, "complete", key, input);
        if (previous) return Receipt.parse(previous);
        const [row] =
          await sql`select * from onboarding_states where athlete_id=${owner}`;
        if (row?.completion)
          throw new ApiError(
            409,
            "ONBOARDING_ALREADY_COMPLETED",
            "Recover your existing receipt with GET /v1/onboarding.",
          );
        if (
          !row ||
          String(row.revision) !== input.draftRevision ||
          row.athlete_revision !== String(athlete.revision)
        )
          throw new ApiError(
            409,
            "ONBOARDING_REVISION_CONFLICT",
            "Reload and review the current draft/profile before completing setup.",
            { fields: ["draftRevision"] },
          );
        await requireDevice(sql, owner, input.deviceId);
        if (input.catalogVersion !== catalogVersion)
          throw new ApiError(
            409,
            "UNSUPPORTED_CATALOG_MAPPING",
            "Refresh the catalog and review all selected IDs.",
            { fields: ["catalogVersion"] },
          );
        const [policy] =
          await sql`select config from training_policy_versions where id=${input.policyVersionId} and status in ('published','retired')`;
        if (!policy)
          throw new ApiError(
            422,
            "ONBOARDING_VALIDATION_FAILED",
            "Select an available published policy.",
            { fields: ["policyVersionId"] },
          );
        const rules = OnboardingPolicy.parse(
          policy.config.onboarding ?? legacyOnboardingPolicy,
        );
        const { draft: d, provenance } = await resolveImports(
          sql,
          owner,
          Draft.parse(row.draft),
          "hydrate",
        );
        const now = new Date();
        validateComplete(d, now);
        // An existing training setup belongs to explicit edit/replan flows, never repeat onboarding.
        for (const table of [
          "athlete_details",
          "athlete_training_preferences",
          "athlete_goals",
          "athlete_availability_rules",
          "athlete_equipment",
          "baseline_snapshots",
          "planning_context_snapshots",
          "training_blocks",
        ]) {
          const [existing] =
            await sql`select id from ${sql(table)} where athlete_id=${owner} limit 1`;
          if (existing)
            throw new ApiError(
              409,
              "ONBOARDING_EXISTING_SETUP",
              "This athlete already has training setup. Restore it and use explicit profile/replan flows.",
            );
        }
        for (const [field, table, ids] of [
          ["equipmentIds", "equipment", d.equipmentIds ?? []],
          ["focusMuscleIds", "muscle_groups", d.focusMuscleIds ?? []],
          [
            "details.strengthRecords",
            "exercises",
            d.details.strengthRecords.map((r) => r.exerciseId),
          ],
        ] as const) {
          for (const id of ids) {
            const [record] =
              await sql`select id from ${sql(table)} where id=${id}`;
            if (!record)
              throw new ApiError(
                422,
                "UNSUPPORTED_CATALOG_MAPPING",
                "One or more choices have no canonical catalog mapping.",
                { fields: [field] },
              );
          }
        }
        for (const p of provenance)
          if (
            !p.editedFromSource &&
            ["weeklyDistanceM", "currentStrengthSessionsPerWeek"].includes(
              p.field,
            )
          ) {
            const w = p.observation.window;
            if (
              !w ||
              w.start.slice(0, 10) !== d.baselinePeriod?.start ||
              w.end.slice(0, 10) !== d.baselinePeriod?.end
            )
              invalid(
                ["baselinePeriod"],
                "The baseline period must match the reviewed recent observation window.",
              );
          }
        const saved: z.infer<typeof Receipt>["saved"] = [];
        async function create(
          type: string,
          payload: unknown,
          id: string = crypto.randomUUID(),
          operation = "create",
          baseRevision: string | null = null,
        ) {
          try {
            const revision = await applyMutation(
              sql,
              athlete,
              SyncMutationSchema.parse({
                id: crypto.randomUUID(),
                entityType: type,
                entityId: id,
                operation,
                baseRevision,
                payload,
              }),
            );
            const ref = { entityType: type, id, revision };
            saved.push(ref);
            return ref;
          } catch (e) {
            if (e instanceof ZodError)
              invalid(e.issues.map((i) => `${type}.${i.path.join(".")}`));
            throw e;
          }
        }
        await create(
          "athlete",
          d.profile,
          owner,
          "update",
          String(athlete.revision),
        );
        const details = await create(
          "athlete_details",
          { schemaVersion: 1, details: d.details },
          owner,
        );
        const baselineFields = [
          "weeklyDistanceM",
          "currentStrengthSessionsPerWeek",
        ];
        await sql`update athlete_details set provenance=${sql.json(provenance.filter((p) => !baselineFields.includes(p.field)))} where id=${owner}`;
        const priority = d.priority ?? "balanced",
          runWeight = rules.priorityWeights[priority];
        const preferences = {
          priorityMode: priority,
          runPriorityWeight: runWeight,
          strengthPriorityWeight: 1 - runWeight,
          strengthObjective: d.strengthGoal,
          experienceLevel: null,
          notes: d.context,
          onboarding: {
            runningLevel: d.runningLevel,
            strengthLevel: d.strengthLevel,
            desiredStrengthSessionsPerWeek: d.desiredStrengthSessionsPerWeek,
            focusMuscleIds: d.focusMuscleIds,
            equipmentConfirmed: true,
            readiness: d.readiness,
          },
        };
        await create("training_preferences", preferences, owner);
        const distances = {
          "5k": 5000,
          "10k": 10000,
          half_marathon: 21097,
          marathon: 42195,
        };
        const distance =
          d.runningGoal && d.runningGoal !== "fitness"
            ? distances[d.runningGoal]
            : null;
        const goals = [
          {
            discipline: "running",
            goalType: distance ? "race" : "general_fitness",
            status: "active",
            targetDate: d.raceDate,
            targetValue: distance,
            targetUnit: distance ? "meters" : null,
            priorityRank: 1,
            metadata: distance ? { raceDistanceM: distance } : {},
          },
          {
            discipline: "strength",
            goalType: d.strengthGoal,
            status: "active",
            targetDate: null,
            targetValue: null,
            targetUnit: null,
            priorityRank: 2,
            metadata: {},
          },
        ];
        for (const goal of goals) await create("athlete_goal", goal);
        const availability = Array.from({ length: 7 }, (_, i) => ({
          dayOfWeek: i + 1,
          available: d.availableDays?.includes(i + 1) ?? false,
          maxSessions: d.availableDays?.includes(i + 1) ? 1 : 0,
          minSessionMinutes: null,
          maxSessionMinutes: d.availableDays?.includes(i + 1)
            ? d.sessionMinutes
            : null,
          preference: "neutral",
        }));
        for (const rule of availability)
          await create("availability_rule", rule);
        for (const equipmentId of d.equipmentIds ?? [])
          await create("athlete_equipment", { equipmentId, available: true });
        const baselineProvenance = provenance.filter((p) =>
          baselineFields.includes(p.field),
        );
        const sources = new Set(
          baselineFields.map(
            (field) =>
              baselineProvenance.find((p) => p.field === field)?.source ??
              "manual",
          ),
        );
        const source =
          sources.size > 1 ? "mixed" : ([...sources][0] ?? "manual");
        const metrics = {
          onboardingMetricsVersion: 1,
          weeklyDistanceM: d.weeklyDistanceM,
          currentStrengthSessionsPerWeek: d.currentStrengthSessionsPerWeek,
        };
        const baseline = await create("baseline_snapshot", {
          schemaVersion: 1,
          periodStart: d.baselinePeriod?.start,
          periodEnd: d.baselinePeriod?.end,
          metrics,
          confidence: { reviewed: true },
          source,
          confirmedAt: now.toISOString(),
        });
        await sql`update baseline_snapshots set provenance=${sql.json(baselineProvenance)} where id=${baseline.id}`;
        const context = await create("planning_context_snapshot", {
          schemaVersion: 1,
          baselineSnapshotId: baseline.id,
          policyVersionId: input.policyVersionId,
          snapshot: {
            goals,
            preferences,
            availabilityRules: availability,
            availabilityOverrides: [],
            equipmentIds: d.equipmentIds,
            recentFeatures: metrics,
            athleteDetailsId: details.id,
            athleteDetailsSnapshot: {
              revision: details.revision,
              details: d.details,
            },
          },
        });
        const [sequence] =
          await sql`select max(sequence)::text as value from sync_change_log where athlete_id=${owner}`;
        const unsupported =
          (d.weeklyDistanceM ?? 0) < rules.minimumWeeklyDistanceM ||
          (d.weeklyDistanceM ?? 0) > rules.maximumWeeklyDistanceM;
        const receipt = Receipt.parse({
          submissionId: key,
          choices: {
            wantsHealth: d.wantsHealth,
            wantsStrava: d.wantsStrava,
            membership: d.membership,
          },
          completedAt: now.toISOString(),
          draftRevision: input.draftRevision,
          catalogVersion: input.catalogVersion,
          policyVersionId: input.policyVersionId,
          athleteDetails: details,
          baseline,
          planningContext: context,
          saved,
          latestSequence: String(sequence?.value ?? "0"),
          planning: {
            status: unsupported
              ? "unsupported_baseline"
              : "ready_for_local_planner",
            reason: unsupported
              ? "weekly_distance_outside_planner_range"
              : null,
            minimumWeeklyDistanceM: rules.minimumWeeklyDistanceM,
            maximumWeeklyDistanceM: rules.maximumWeeklyDistanceM,
          },
        });
        await sql`update onboarding_states set draft=null,completion=${sql.json(receipt)},step='membership',updated_at=now() where athlete_id=${owner}`;
        await remember(sql, owner, "complete", key, input, receipt);
        return receipt;
      }),
  };
}
