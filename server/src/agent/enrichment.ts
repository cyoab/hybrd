import type postgres from "postgres";
import {
  hash,
  insertRow,
  owned,
  type Row,
  stableJson,
  type Tx,
} from "../db/store";
import { readWorkoutPrescription } from "../domain/read";
import { fail, manifestFor } from "./planning";
import {
  AnalysisPacket,
  DeviceChallenge,
  MemoryCandidate,
  type RunInputV2,
} from "./v2-schemas";

export async function learnMemories(
  sql: Tx,
  athlete: Row,
  run: Row,
  candidates: unknown[],
) {
  const athleteId = String(athlete.id);
  const [settings] =
    await sql`select enabled from agent_memory_settings where athlete_id=${athleteId}`;
  if (!settings?.enabled) return;
  const message = String((run.request as Row).message);
  for (const raw of candidates.slice(0, 3)) {
    const c = MemoryCandidate.parse(raw);
    // Store only an exact athlete-authored quote. No inference becomes a constraint.
    if (
      !message.includes(c.sourceQuote) ||
      c.content !== c.sourceQuote ||
      /diagnos|disease|medicat|dosis|enfermed|embaraz|pregnan|injur|lesi[oó]n|ignore|system|instruction|prompt|secret|password/i.test(
        c.content,
      )
    )
      continue;
    if (
      c.category === "temporary_constraint" &&
      (!c.expiresAt || Date.parse(c.expiresAt) > Date.now() + 30 * 86400000)
    )
      continue;
    if (c.expiresAt && Date.parse(c.expiresAt) <= Date.now()) continue;
    const [size] =
      await sql`select count(*)::int n,coalesce(sum(length(content)),0)::int chars from athlete_memories where athlete_id=${athleteId}`;
    if (Number(size?.n) >= 20 || Number(size?.chars) + c.content.length > 5000)
      break;
    const digest = hash({
      run: run.id,
      quote: c.sourceQuote,
      category: c.category,
    });
    const id = `${digest.slice(0, 8)}-${digest.slice(8, 12)}-4${digest.slice(13, 16)}-8${digest.slice(17, 20)}-${digest.slice(20, 32)}`;
    await sql`insert into athlete_memories(id,athlete_id,category,content,source,expires_at,source_run_id,source_message_id,source_quote,confidence) values(${id},${athleteId},${c.category},${c.content},'learned',${c.expiresAt},${String(run.id)},${String(run.user_message_id)},${c.sourceQuote},${sql.json(c.confidence)}) on conflict(id) do nothing`;
  }
}
export async function putAnalysisPacket(sql: Tx, athlete: Row, raw: unknown) {
  const p = AnalysisPacket.parse(raw),
    athleteId = String(athlete.id);
  if (!athlete.cloud_ai_consent)
    fail(
      "AI_CONSENT_REQUIRED",
      "Cloud AI consent is required for detailed analysis uploads.",
    );
  const [device] =
    await sql`select id from device_installations where id=${p.deviceId} and athlete_id=${athleteId} and revoked_at is null`;
  if (!device) fail("DEVICE_UNAVAILABLE", "Register this recording device.");
  const result = await owned(sql, "workout_results", p.resultId, athleteId);
  if (
    String(result.revision) !== p.resultRevision ||
    result.planned_workout_id !== p.plannedWorkoutId
  )
    fail(
      "WORKOUT_REVISION_CONFLICT",
      "Packets must reference the current result and its historical prescription.",
    );
  if (
    (result.started_at &&
      new Date(String(result.started_at)).getTime() !==
        Date.parse(p.startedAt)) ||
    (result.ended_at &&
      new Date(String(result.ended_at)).getTime() !== Date.parse(p.endedAt)) ||
    (result.duration_s != null &&
      Math.abs(Number(result.duration_s) - p.elapsedDurationS) > 2)
  )
    fail(
      "ANALYSIS_RESULT_MISMATCH",
      "Packet recording times must match the referenced result.",
    );
  const { checksum, ...unsigned } = p;
  if (hash(unsigned) !== checksum)
    fail(
      "ANALYSIS_CHECKSUM_MISMATCH",
      "Checksum must be SHA-256 of canonical sorted JSON without checksum.",
    );
  if (Buffer.byteLength(stableJson(p)) > 262144)
    fail(
      "ANALYSIS_PACKET_TOO_LARGE",
      "Analysis packets are limited to 256 KiB; aggregate with explicit coverage omissions.",
    );
  const elapsed = (Date.parse(p.endedAt) - Date.parse(p.startedAt)) / 1000;
  if (
    elapsed < 0 ||
    Math.abs(elapsed - p.elapsedDurationS) > 2 ||
    (p.activeDurationS != null && p.activeDurationS > p.elapsedDurationS) ||
    (p.movingDurationS != null &&
      p.movingDurationS > (p.activeDurationS ?? p.elapsedDurationS))
  )
    fail(
      "ANALYSIS_TIMING_INVALID",
      "Elapsed, active and moving durations must be consistent.",
    );
  if (
    (p.coverage.heartRate === "none" ||
      p.coverage.heartRate === "summary_only") &&
    p.heartRate.length
  )
    fail(
      "ANALYSIS_COVERAGE_INVALID",
      "Summary-only heart rate cannot contain a fabricated trace.",
    );
  if (p.coverage.heartRate === "complete" && p.heartRate.length < 2)
    fail(
      "ANALYSIS_COVERAGE_INVALID",
      "Complete coverage requires measured samples.",
    );
  for (let i = 0; i < p.heartRate.length; i++) {
    const s = p.heartRate[i]!;
    if (
      s.elapsedS > p.elapsedDurationS ||
      (i > 0 && s.elapsedS <= p.heartRate[i - 1]!.elapsedS)
    )
      fail(
        "ANALYSIS_TIMING_INVALID",
        "Heart-rate samples require increasing elapsed offsets within the recording.",
      );
  }
  if (
    p.coverage.heartRate === "complete" &&
    (p.heartRate[0]!.elapsedS > 30 ||
      p.elapsedDurationS - p.heartRate[p.heartRate.length - 1]!.elapsedS > 30 ||
      p.heartRate.some(
        (sample, i) =>
          i > 0 && sample.elapsedS - p.heartRate[i - 1]!.elapsedS > 30,
      ))
  )
    fail(
      "ANALYSIS_COVERAGE_INVALID",
      "Complete HR coverage cannot contain unreported gaps longer than 30 seconds. Use partial coverage with omission reasons.",
    );
  const prescription = p.plannedWorkoutId
    ? await readWorkoutPrescription(sql, p.plannedWorkoutId)
    : null;
  const bounds = new Map<string, { time: number; distance: number }>();
  const seen = new Set<string>();
  for (const b of p.boundaries) {
    const prev = bounds.get(b.series);
    if (
      p.activeDurationS == null ||
      b.activeSeconds > p.activeDurationS ||
      (prev &&
        (b.activeSeconds < prev.time || b.cumulativeMeters < prev.distance))
    )
      fail(
        "ANALYSIS_TIMING_INVALID",
        "Boundary offsets use monotonically increasing active time and cumulative meters within each independent series.",
      );
    bounds.set(b.series, {
      time: b.activeSeconds,
      distance: b.cumulativeMeters,
    });
    if (b.series === "prescription_interval") {
      const run = prescription?.run as
        | {
            blocks?: {
              id: string;
              repeatCount: number;
              steps: { id: string }[];
            }[];
          }
        | undefined;
      const block = run?.blocks?.find((x) => x.id === b.blockId);
      if (
        !block ||
        b.repeatIteration == null ||
        b.repeatIteration >= block.repeatCount ||
        !block.steps.some((s) => s.id === b.stepId)
      )
        fail(
          "ANALYSIS_PRESCRIPTION_MISMATCH",
          "Intervals must use original block/step IDs and zero-based repeat iteration.",
        );
      const identity = `${b.blockId}/${b.stepId}/${b.repeatIteration}`;
      if (seen.has(identity))
        fail(
          "ANALYSIS_DUPLICATE_INTERVAL",
          "Prescription interval completions must be unique.",
        );
      seen.add(identity);
    } else if (b.blockId || b.stepId || b.repeatIteration != null)
      fail(
        "ANALYSIS_PRESCRIPTION_MISMATCH",
        "Splits and laps do not identify prescription intervals.",
      );
  }
  const [prior] =
    await sql`select packet from agent_analysis_packets where result_id=${p.resultId} and athlete_id=${athleteId}`;
  if (prior && prior.packet.checksum === checksum)
    return { checksum, status: "stored" as const };
  if (prior && prior.packet.resultRevision === p.resultRevision)
    fail(
      "ANALYSIS_PACKET_CONFLICT",
      "One immutable packet is accepted per result revision. Correct the result before replacing it.",
    );
  await sql`insert into agent_analysis_packets(result_id,athlete_id,result_revision,packet) values(${p.resultId},${athleteId},${p.resultRevision},${sql.json(p)}) on conflict(result_id) do update set packet=excluded.packet,result_revision=excluded.result_revision,created_at=now()`;
  return { checksum, status: "stored" as const };
}
export async function analysisDetails(
  sql: Tx,
  athleteId: string,
  resultId: string,
  revision: string,
) {
  const [row] =
    await sql`select packet from agent_analysis_packets where athlete_id=${athleteId} and result_id=${resultId} and result_revision=${revision}`;
  if (!row) return null;
  const p = AnalysisPacket.parse(row.packet),
    metrics: { ref: string; value: number; unit: string; label: string }[] = [];
  const add = (
    key: string,
    value: number | null,
    unit: string,
    label: string,
  ) => {
    if (value != null)
      metrics.push({
        ref: `${resultId}@${revision}:packet.${key}`,
        value,
        unit,
        label,
      });
  };
  add(
    "activeDurationS",
    p.activeDurationS,
    "seconds",
    "Measured active duration, excluding paused time",
  );
  add(
    "elapsedDurationS",
    p.elapsedDurationS,
    "seconds",
    "Elapsed recording duration",
  );
  add(
    "movingDurationS",
    p.movingDurationS,
    "seconds",
    "Measured moving duration",
  );
  // Integrate only observed adjacent intervals <=30 seconds; uncovered gaps are never imputed.
  let covered = 0,
    integral = 0;
  for (let i = 1; i < p.heartRate.length; i++) {
    const a = p.heartRate[i - 1]!,
      b = p.heartRate[i]!,
      dt = b.elapsedS - a.elapsedS;
    if (dt <= 30) {
      covered += dt;
      integral += ((a.bpm + b.bpm) / 2) * dt;
    }
  }
  add(
    "hrObservedSeconds",
    covered,
    "seconds",
    "Heart-rate sample coverage with gaps over 30s excluded",
  );
  if (covered > 0)
    add(
      "hrTimeWeightedMean",
      integral / covered,
      "bpm",
      "Time-weighted mean over observed intervals only",
    );
  return {
    schemaVersion: p.schemaVersion,
    algorithmVersion: p.algorithmVersion,
    checksum: p.checksum,
    source: p.source,
    recordingId: p.recordingId,
    units: p.units,
    coverage: p.coverage,
    metrics,
    boundaries: p.boundaries.slice(0, 100),
    boundaryCoverage: {
      returned: Math.min(100, p.boundaries.length),
      total: p.boundaries.length,
      selection: "first_100_by_upload_order",
    },
    limitations: [
      ...(p.boundaries.length > 100
        ? [
            "Only the first 100 uploaded boundaries appear in this bounded context; later boundaries require a paged detail read.",
          ]
        : []),
      "HR drift and zone time are not inferred from summary HR or incomplete traces.",
      "Boundary active seconds exclude pauses; they are not wall-clock offsets. Splits, laps and prescription intervals can overlap.",
      ...p.coverage.omissions,
    ],
  };
}
export async function prepareChallenge(
  sql: Tx,
  athlete: Row,
  run: Row,
  input: RunInputV2,
) {
  const scope = input.native!;
  const m = await manifestFor(sql, String(athlete.id), scope.deviceId);
  if (!m.deviceActions.includes(scope.action))
    fail(
      "DEVICE_ACTION_UNSUPPORTED",
      "This device does not advertise the requested action.",
    );
  if (
    scope.action === "start" &&
    (scope.expectedLocalState !== "idle" || !scope.plannedWorkoutId)
  )
    fail(
      "DEVICE_STATE_CONFLICT",
      "Starting requires an idle device and canonical workout.",
    );
  if (scope.action !== "start" && scope.expectedLocalState === "idle")
    fail(
      "DEVICE_STATE_CONFLICT",
      "This action requires the identified active recording.",
    );
  if (scope.plannedWorkoutId) {
    const [w] =
      await sql`select w.id from planned_workouts w join plan_versions p on p.id=w.plan_version_id where w.id=${scope.plannedWorkoutId} and p.athlete_id=${String(athlete.id)}`;
    if (!w) fail("REFERENCE_UNAVAILABLE", "Workout unavailable.");
  }
  const id = crypto.randomUUID(),
    expiresAt = new Date(Date.now() + 120000).toISOString();
  const challenge = DeviceChallenge.parse({
    id,
    runId: run.id,
    scope,
    digest: hash({
      id,
      athleteId: athlete.id,
      runId: run.id,
      scope,
      expiresAt,
    }),
    status: "pending",
    expiresAt,
    result: null,
  });
  await insertRow(sql, "agent_device_challenges", {
    id,
    athleteId: athlete.id,
    runId: run.id,
    deviceId: scope.deviceId,
    challenge,
  });
  return challenge;
}
export async function acknowledgeChallenge(
  sql: Tx,
  athlete: Row,
  id: string,
  key: string,
  input: {
    deviceId: string;
    digest: string;
    claimToken: string;
    recordingId: string;
    status: "executed" | "rejected" | "unavailable";
    localState: "idle" | "recording" | "paused" | "finished";
    reason: string | null;
  },
) {
  const row = await owned(
      sql,
      "agent_device_challenges",
      id,
      String(athlete.id),
    ),
    c = DeviceChallenge.parse(row.challenge),
    fingerprint = hash(input);
  if (row.ack_key) {
    if (row.ack_key !== key || row.ack_hash !== fingerprint)
      fail(
        "DEVICE_ACK_CONFLICT",
        "The challenge has already been acknowledged.",
      );
    return c;
  }
  await manifestFor(sql, String(athlete.id), input.deviceId);
  if (
    c.scope.deviceId !== input.deviceId ||
    c.scope.recordingId !== input.recordingId ||
    c.digest !== input.digest
  )
    fail(
      "DEVICE_CHALLENGE_MISMATCH",
      "Device, recording and exact action digest must match.",
    );
  if (Date.parse(c.expiresAt) <= Date.now())
    fail(
      "DEVICE_CHALLENGE_EXPIRED",
      "The action expired; no execution may be claimed.",
    );
  if (c.status !== "claimed" || c.claimToken !== input.claimToken)
    fail(
      "DEVICE_ACK_CONFLICT",
      "Claim this challenge before acknowledging execution.",
    );
  const states = {
    start: "recording",
    pause: "paused",
    resume: "recording",
    lap: c.scope.expectedLocalState,
    finish: "finished",
  };
  if (
    input.status === "executed" &&
    input.localState !== states[c.scope.action]
  )
    fail(
      "DEVICE_STATE_CONFLICT",
      "Execution receipt does not match the requested resulting state.",
    );
  c.status = input.status;
  c.result = { localState: input.localState, reason: input.reason };
  await sql`update agent_device_challenges set challenge=${sql.json(c as unknown as postgres.JSONValue)},ack_key=${key},ack_hash=${fingerprint} where id=${id}`;
  return c;
}
