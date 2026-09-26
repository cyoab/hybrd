# Training agent API

Implemented backend contract, 25 September 2026. This document and [OpenAPI](../contracts/openapi.yaml) supersede the proposed endpoints in the [architecture plan](ai-agent-implementation-plan.md). Native implementation remains owned by the parallel iOS task. No Swift files are changed by this backend delivery.

## Versions and availability

The API URL remains `/v1`. **Agent schema v2 is explicitly selected using `/v1/agent/v2/*`**. These are distinct from canonical prescription schema version **1** and native executable version **2**. Unnegotiated `GET /v1/agent/capabilities` still returns schemaVersion 1 with `create_plan:false`, `modify_plan:false`, and `memory:"manual"`. Existing v1 chat, analysis, memory editing and SSE continue to work. Reserved v1 mutation requests still fail without a model call.

V2 supports structured complete plan creation, draft acceptance, direct scoped edits, recurring exercise choices, compensating Undo, detailed workout analysis, opt-in memory learning and typed native action challenges. Capability flags indicate backend environment availability; consent, entitlement, device support and current revisions are checked independently. Never enable native UI based solely on a v2 endpoint existing.

Canonical plans, changes, threads and messages use the existing sync entities. Agent runs, receipts, memories, packets, device manifests and challenges **do not introduce unknown entities into the legacy sync feed**. A v2 run wraps the existing schemaVersion 1 textual/citation artifact and adds typed `action`, `deviceChallenge` and `learnedMemoryIds` fields. These fields are the authority for applied actions, not assistant prose.

## Development and rollout

Apply migrations through `0009` and reseed the catalog (`make migrate`, or `bun run db:migrate && bun run db:seed` inside the dev API container). Catalog v3 appends incline barbell/dumbbell presses and an adjustable bench; existing catalog IDs retain their meanings. The worker still runs within the API process. Persistent Docker dev services remain **API + PostgreSQL**; no additional queue, vector store or mail container is required.

```dotenv
AGENT_ENABLED=true
OPENROUTER_API_KEY=YOUR_SERVER_ONLY_KEY
OPENROUTER_JEV_MODEL=YOUR_TESTED_JEV_ROUTE
AGENT_MODEL=YOUR_TESTED_TOOL_CAPABLE_MODEL
AGENT_CACHE_MODE=automatic
AGENT_SCOPE_CONFIDENCE=0.8
AGENT_MAX_GENERATIVE_CALLS=4
```

`AGENT_MODEL` falls back to `OPENROUTER_LLM_MODEL`. Recreate the API container after changing environment configuration. Agent defaults off; use a published policy with `remoteCoach`, registered installation, `cloudAiConsent:true` and active/grace coaching entitlement (`pro` by default). Tests inject providers and do not send athlete data to a live model. This delivery does not publish a clinically qualified dosing policy or claim live provider/model calibration. The development policy's example load percentages/interference hours are not enforced as established scientific safety rules.

All endpoints require the existing bearer session, return the existing private/no-store error envelope and enforce account ownership. Model API keys remain server-only. UUID idempotency keys are headers. The model has neither arbitrary SQL/code execution nor a tool for accepting its own authorization scope.

## V2 endpoints

All paths in this table are prefixed with `/v1/agent/v2`.

| Method and path | Behavior |
| --- | --- |
| `GET /capabilities` | Negotiated versions, task availability, consent/entitlement requirements and budgets. |
| `PUT /device-manifest` | Register this installation's executable features/limits; expires after 24 hours. Phone and Watch manifests are independent. |
| `GET /planning-context?trainingBlockId=UUID` | Current profile revision, context token, blocks, explicit exercise rules, and optional full current block prescriptions. |
| `POST /runs` | `Idempotency-Key`; durable `202 AgentRunV2`, no provider call on the HTTP request path. |
| `GET /runs/{id}` | Restore status, typed receipt, challenge and memory IDs. |
| `GET /runs?before=UUID` | Up to 20 owned runs per page; `nextBefore` supports recovery across installations. |
| `GET /requests/{idempotencyKey}` | Lookup the original request without replaying POST or starting paid work. |
| `POST /requests/{idempotencyKey}/cancel` | Cancel an existing run only. A missing key creates nothing; committed actions remain committed. |
| `POST /actions/{id}/apply` | `Idempotency-Key`; explicitly accept a validated draft using fresh context/head and local protections, without another AI call. |
| `POST /actions/{id}/undo` | `Idempotency-Key`; compensate an action within seven days, preserving unrelated later edits. |
| `DELETE /exercise-rules/{fromExerciseId}?expectedRevision=decimal` | Remove a recurring choice for future generation; existing plans are unchanged. |
| `PUT /analysis-packet` | Upload one immutable detailed packet per owned result revision; exact checksum replay deduplicates. |
| `GET /memory-settings` | Learning defaults off; returns revision. |
| `PUT /memory-settings` | `{enabled,expectedRevision}`; separate explicit opt-in/revocation. |
| `GET /memories` | Visible entries with provenance, exact quote, confidence, revision and expiry. |
| `POST /device-challenges/{id}/claim` | `Idempotency-Key`; atomically claim a pending command immediately before native execution. |
| `POST /device-challenges/{id}/ack` | `Idempotency-Key`; submit exact device/recording/digest/claimToken and local execution result. |
| `POST /device-challenges/{id}/cancel` | Cancel pending commands. Claimed/acknowledged commands are returned unchanged. |

Continue using the existing `GET /v1/agent/runs/{id}/events` SSE and `POST /v1/agent/runs/{id}/cancel`. Existing `PUT /v1/agent/memories/{id}` and `DELETE /v1/agent/memories/{id}` provide edit/forget; DELETE requires `If-Match` with the unquoted revision. V1 memory listing shows manual entries; v2 listing also exposes learned provenance.

## Plan creation and modification

1. Register a fresh manifest for the **initiating device**. Distinguish phone/Watch, app build, paired installation, executable version, maximum expanded steps/result segments, supported completion conditions, rich strength and native actions. A phone's capabilities never imply its Watch's capabilities.
2. Drain the local sync outbox, pull/apply canonical changes, then fetch planning context. Send `outboxDrained:true`, the returned `contextToken`, profile revision, expected active head and every logical workout pinned by an active local recording. A context token fingerprints profile, training preferences, goals, availability, overrides, equipment, exclusions, rules, block heads, results, baseline, reviewed details and policy. The server rechecks it throughout the run and immediately before commit.
3. For `create_plan`, specify a new block with null block/head IDs, explicit dates (maximum 16 weeks), and `mode:"draft"` or `mode:"apply"`. Default the UI to draft unless the athlete explicitly asked to create and start. Creation never silently replaces another block. To modify an existing block, send its current IDs, a bounded date range and the precise allowed operations: `move`, `replace_exercise`, `replace_workout`, `remove`, `add`. Enable `allowRecurringPreference` only for an explicit lasting preference. Ambiguous scope must be clarified, not enlarged by the model.
4. The model returns a strict `AgentPlanBlueprint` with reusable complete templates and dated instances. The backend allocates UUIDs, expands every session, validates canonical inputs and produces a real immutable draft/version. Complete-horizon checks reject missing weeks. This is not a prose plan or an instruction for iOS to invent activities.
5. Final output and proposed changes undergo Jev scope/intent review, followed by deterministic authorization/context checks. A savepoint makes plan/context/block writes, preferences, activation, receipt, canonical sync events and assistant publication atomic. Failed completion cannot leave a partly applied plan.
6. Read the typed action receipt. It contains lifecycle (`draft`, `applied`, `undone`), canonical block/plan IDs, resulting plan revision, concrete added/removed/moved/prescription-change IDs, reasons, resolved citations, validation issues, compatibility versions and Undo expiry. `syncRequired:true` is an invalidation hint, **never a new sync cursor**. Pull canonical plan/workout data before rendering executable activities.
7. To accept a draft, submit fresh context/head, device ID, `outboxDrained:true` and protected logical IDs to `/actions/{id}/apply`. A verified server action authorization permits coach-origin activation. No fabricated accepted proposal or client-controlled acceptance bypass is used. Existing proposal-based activation remains supported.

The compiler preserves fractional pace/RPE/load targets, sets, supersets, substitutions, repeated run blocks and discipline. It rejects unavailable equipment, excluded exercises, incompatible movement families, recorded/protected session changes, availability/session-duration violations, invalid ranges and unsupported execution. It requires reviewed preferences and all seven availability days. Exercise substitutions clear transferred absolute loads and prescribe effort instead. Unsupported percentage-of-E1RM generation is rejected until a verified E1RM path exists; recent recorded external loads bound generated absolute loads. Recurring incline choices affect matching horizontal presses, including future generation; overhead presses retain their movement family.

Current native completion semantics are **one positive duration OR distance** per generated run step. Combined first-of/all-of conditions are rejected. Expanded run steps must fit both manifest limits (currently at most 2,000 executable steps and 500 v1 result segments). Prescriptions are bounded to 300 sessions and 20,000 nested rows. Native substitutions remain stored alternatives; backend validation does not claim the app can execute interactive substitutions.

Every version receives new physical prescription IDs; unchanged sessions retain logical IDs and all targets. Recorded history and active native snapshots stay pinned to their original physical block/step/exercise/set IDs. Repeat iteration is zero-based. Late actuals against superseded accepted versions remain valid; an unrelated later plan edit preserves the accepted head while leaving that historical execution intact. The backend cannot discover a recording started on another device while offline. iOS must never remap its results to a newer prescription.

Relative training dates use the athlete's timezone and optional training-day boundary. Blueprint dates are explicit calendar dates; generation leaves `scheduledStartAt:null` rather than inventing UTC instants around DST. A move clears an obsolete scheduled instant. Native scheduling remains responsible for explicit local time choices.

Undo compares affected sessions and recurring-rule revisions with the committed action. It creates a compensating version while keeping unrelated later changes. Later edits to the same session, a new recorded result, changed recurring rule, pinned recording, stale context/head or expiry produce an explicit conflict. Undo never rewinds the sync cursor or reactivates a superseded version. Undoing an untouched newly created plan cancels that new block; undoing a draft marks it rejected. Cancellation never means Undo.

## Analysis packets and data tools

Sync a result first and request analysis with its exact ID/revision. Original prescriptions, actual per-set/per-segment values and coverage are available through bounded tools. Observations reference deterministic `resultId@revision:metricKey` identifiers. Corrected/deleted results make old artifacts `artifactStale:true`.

Optional packets additionally bind device, result/revision, original planned workout, recording ID, source (`iphone`, `watch`, `healthkit`, `manual`), recording times, units, schema/algorithm version and `consentVersion:1`. Consent represents a client disclosure for uploading these details; it does not replace cloud AI consent or native Health permissions. Source labels describe client-provided provenance, not independent proof of sensor accuracy.

Limits: **256 KiB**, 1,000 HR samples, 2,000 boundaries. Upload the whole packet, with SHA-256 over recursively key-sorted canonical JSON excluding `checksum`. There is no chunk endpoint. If native data exceeds these limits, provide an explicitly aggregated packet and coverage/omission reasons; never silently truncate or relabel a summary as a complete trace. A differing packet for the same revision conflicts; correct the canonical result before replacing it.

Elapsed, active and moving durations are separate and validated against the result. HR samples use increasing elapsed offsets. Interval boundaries use cumulative **active seconds and meters**, not wall-clock offsets. Prescription intervals, automatic splits and manual laps are separate potentially overlapping series. Original block/step IDs and zero-based repeat indices are checked, including duplicate interval rejection. Exact GPS fields are rejected.

Tools compute elapsed/moving pace, actual completed-set metrics, active/elapsed/moving durations and time-weighted HR over observed adjacent sample intervals of at most 30 seconds. Missing HR is not imputed; no drift or zone-time estimate is invented from summary HR. Broad detail reads explicitly report omitted counts; paged tools retrieve actuals, original prescriptions and packet boundaries as needed. Limits are part of the answer's interpretation. Packets expire after 90 days and stale/deleted-result packets are pruned; canonical actuals remain subject to normal account retention.

## Memory and recurring choices

Automatic learning is **off by default**, independent of coaching/HealthKit consent. With opt-in, the model can stage at most three exact current-athlete quotes about training/communication preferences. Only matching quotes are saved; inferred diagnoses, instructions and secrets are excluded. Entries record source run/message, confidence, exact quote, revision and optional expiry. Learned IDs are deterministic for run/quote/category, making retries harmless. Temporary constraints require an expiry within 30 days.

The combined memory budget is 20 entries/5,000 characters. The run uses a frozen bounded memory prefix. An on-demand owned session search retrieves at most four recent matching excerpts after the memory-reset/expiry boundary. Retrieved history cannot authorize learning. This adopts bounded curated memory and selective history retrieval rather than unbounded transcript replay.

Edit/forget cancels pending runs with `MEMORY_CONTEXT_CHANGED`, clears prompt checkpoints and excludes older history from future prompts/search. Revoking learning also deletes learned entries; manually entered notes remain available for explicit edit/forget. Historical messages remain visible to the athlete, but are not silently fed back into subsequent prompts across that boundary. Provider-side cache retention follows the configured provider contract; the application does not claim remote physical cache erasure.

Memory never changes canonical training preferences. Explicit recurring exercise rules are separately typed, revisioned and committed with the requested plan change. Inspect them through planning context, remove them with the rule endpoint, or change them through another authorized plan edit. Account export includes runs, memory/settings, receipts, exercise rules, detailed packets and device challenges; account deletion cascades through all these records.

## Native actions

A `device_action` run contains an exact `native` scope: registered target device, allowlisted action (`start`, `pause`, `resume`, `lap`, `finish`), recording ID, optional canonical workout and expected local state. A successful run only creates a **pending** 120-second challenge. It does not start a sensor or confirm execution.

Native must check its own installation, digest, exact recording, permissions, foreground confirmation and local state. Immediately before execution, claim with the same device/recording/digest and a persisted idempotency key. The backend atomically changes pending to claimed and returns a claim token. Persist the claim locally, perform the command at most once, then acknowledge using that token and another persisted idempotency key. An uncertain claim/ack response is looked up/retried with the same key; never repeat a physical effect simply because a network response was lost.

Pending cancellation prevents a later claim. A claimed command cannot be remotely recalled; cancellation returns its current state honestly. An unclaimed challenge expires; an expired claimed challenge is `indeterminate` because the backend lacks an execution receipt. Acknowledgments validate final local state and cannot affect a different recording. The Watch can be asleep/offline: show pending/expired/unavailable/indeterminate, never inferred success. Poll the owning v2 run to restore command status; no arbitrary code, UI coordinates, filesystem or sensor access is exposed to the model.

## Streaming, recovery and cost

SSE retains the existing `status`, `tool_status`, `artifact_ready`, `completed`, `failed`, `cancelled` event names; `AgentEvent` is now explicitly exported in OpenAPI. Staging/validation appears as typed tool progress. On artifact/completion, GET the **v2** run for its receipt/challenge. No partial model JSON or reasoning becomes executable. There is no WebSocket requirement and no new event variants for old native decoders to reject.

Persist request body/key before POST. An exact retry returns the same reserved or terminal run. After a lost response, use request-key lookup; cancellation-by-key must not replay create. List pagination restores rich history alongside canonical messages. Keep decimal SSE event IDs separate from sync cursors, deduplicate by `(runId,id)`, and reconnect after the 25-second stream rotation with `Last-Event-ID`. Heartbeats/error frames have no cursor. Seven-day replay expiry requires GET recovery.

Runs terminate as succeeded/failed/cancelled/indeterminate. Worker leases and fencing prevent two workers executing a step. Every provider call is reserved before dispatch. Unknown paid-call outcomes are terminal indeterminate and are **never automatically retried**. Explicit user retry uses a new run key. Final action/run publication is atomic, so lost responses are recoverable without ambiguous backend mutation outcomes.

Budgets: at most four generative calls, eight tool calls, one plan-validation repair, 192 KiB of conversation messages, 3 MB persisted checkpoint and 96 KiB deduplicated plan-review context. Ordinary output is capped at 3,000 tokens; plan-tool turns at 10,000. Reused templates avoid paying for repeated full prescriptions in review. Per-athlete daily/minute quotas and two-pending-run cap still apply. Operational run requests/checkpoints expire after 30 days; final receipts/artifacts remain account data.

Stable prefixes, provider-supported cache hints and opaque conversation routing support reuse; [OpenRouter's caching contract](https://openrouter.ai/docs/guides/best-practices/prompt-caching) does not guarantee hits. Provider fallback is disabled. Ledger fields distinguish total input, cache reads/writes, output/reasoning tokens, latency and reported cost; absent provider usage stays unknown.

Scientific citations resolve through a server-owned registry, with claim summaries and applicability limitations. Identifier validation does not prove scientific entailment. Jev scope/intent classification is an additional check; deterministic ownership, tool scope, revisions and executable constraints enforce authority independently. Live model quality, safety-language calibration and scientific claim evaluation remain rollout work, not properties established by mocked-provider tests.

## Shared examples and iOS next step

Examples use synthetic IDs and fingerprints; fetch real context and manifests rather than posting them unchanged.

- [Create request](../contracts/examples/agent-v2-create.json), [direct edit](../contracts/examples/agent-v2-edit.json), [structured blueprint](../contracts/examples/agent-v2-blueprint.json).
- [Validated draft](../contracts/examples/agent-v2-run-draft.json), [applied action](../contracts/examples/agent-v2-run-applied.json), [Undo receipt](../contracts/examples/agent-v2-action-undone.json).
- [Phone manifest](../contracts/examples/agent-v2-device-manifest.json), [different Watch capabilities](../contracts/examples/agent-v2-watch-manifest.json).
- [Pending challenge](../contracts/examples/agent-v2-device-challenge.json), [claimed](../contracts/examples/agent-v2-device-claimed.json), [executed](../contracts/examples/agent-v2-device-executed.json), [expired](../contracts/examples/agent-v2-device-expired.json).
- [Detailed analysis packet](../contracts/examples/agent-v2-analysis-packet.json), [conflict/unsupported/expiry/replay errors](../contracts/examples/agent-v2-errors.json).
- Existing [v1 request](../contracts/examples/agent-run.json) and [v1 analysis](../contracts/examples/agent-run-succeeded.json) remain supported.

The iOS task can regenerate wire types, implement explicit v2 negotiation, receipt/diff/Undo UI, separate memory consent and packet upload against these schemas. Keep native execution adapters gated until their manifest honestly advertises each capability. Existing pinned-history, DST and repeated-step fixtures remain authoritative. Do not present provider configuration, model calibration or unfinished native v2 adapters as already tested end to end.
