# iOS contract review for the training agent

Research and proposed implementation contract, 2026-09-25. Reviewed the repository at `d8e7e39`; no application code was changed. This is an independent review of the iOS implementation, not approval from the agent that owns the iOS work. The related server architecture is in [AI implementation plan](ai-agent-implementation-plan.md).

## Decision

The backend should orchestrate the agent, retrieve training evidence, construct and validate complete structured plans, and commit authorized changes. iOS and watchOS should execute supported prescriptions, record actual activity, and remain usable offline. The same typed capabilities should serve ordinary screens and agent requests. An agent does not get arbitrary Swift execution, unrestricted UI control, or direct database writes.

This changes the earlier assumption that all plan generation belongs to the on-device starter engine. That engine remains useful as an explicitly labeled offline starter option and deterministic reference, but it is not a science-grounded adaptive planning engine.

The first release dependency is **lossless executable prescription support**. The existing server schema is substantially richer than the native training model. A valid JSON plan can currently decode successfully while losing information needed to perform it. Connecting an LLM to the existing mapping alone would not meet the requested behavior.

## Current implementation

| Area | Observed behavior | References |
| --- | --- | --- |
| Starter generation | Produces four weeks of alternating easy runs and foundational lifting; running volume is reduced in week four. Includes basic equipment/muscle selection. No model call, evidence retrieval, citation objects, or adaptive periodization. | [TrainingEngine.swift](../ios/Shared/TrainingEngine.swift#L14) |
| Plan edits | Add a run and move a workout by making a new plan version; retain logical workout identity. Completed or in-progress workouts are protected in the store. | [TrainingEngine.swift](../ios/Shared/TrainingEngine.swift#L71), [TrainingStore.swift](../ios/App/Models/TrainingStore.swift#L133) |
| Connected state | Account-scoped bootstrap, catalog/policy download, canonical sync records, durable local state and outbox. Outbox presently accepts one batch at a time, with sequential mutations and exact retry. | [BackendAppController.swift](../ios/App/Models/Connected/BackendAppController.swift#L53), [BackendReplica.swift](../ios/App/Models/Backend/BackendReplica.swift#L4) |
| Plan writes | Constructs planning context, block/plan mutations and activation. Rescheduling preserves original wire prescriptions because the native display model is not a lossless editor. | [BackendTrainingWrites.swift](../ios/App/Models/Backend/BackendTrainingWrites.swift#L105) |
| Coach | Local keyword rules with a flat `CoachMessage` list. No cloud request, durable agent run, structured action, citation card, or memory editor. | [CoachView.swift](../ios/App/Views/CoachView.swift), [LocalCoach.swift](../ios/App/Models/LocalCoach.swift), [TrainingStore.swift](../ios/App/Models/TrainingStore.swift#L237) |
| Run execution | Time-based interval timeline, GPS route, native workout session, pause/resume/lap/finish, checkpoint recovery, phone/watch recording. | [RunTimeline.swift](../ios/Shared/RunTimeline.swift), [RunRecording.swift](../ios/Shared/RunRecording.swift), [RunRecorder.swift](../ios/Shared/RunRecorder.swift) |
| Watch transfer | Plan snapshots plus durable recorded-run file transfer; receipt only after iPhone durable save. This is a sound pattern to retain for agent-created plans and richer workout packets. | [CompanionBridge.swift](../ios/Shared/CompanionBridge.swift#L74) |

`BackendTrainingMapping.state` currently constructs the restored `TrainingState` without hydrating coach messages. Existing local conversation storage is not the foundation for durable cloud conversation recovery. Add explicit wire-backed conversation projection rather than treating local messages as the server transcript.

## Prescription parity

The canonical starting point is [server plan schema](../server/src/plans/schemas.ts) and the generated [BackendWire.swift](../ios/App/Models/Backend/Generated/BackendWire.swift). Model output should compile into this domain, with additive versioned extensions where necessary. Keep UUIDs and catalog identity outside free-form prose.

| Domain | Native model can represent now | Information omitted or reduced by current mapping |
| --- | --- | --- |
| Plan | ID, base plan ID, creation time, summary/reason, profile, workouts. | Block phase, policy/context references, origin, citations and generation provenance do not exist on native `TrainingPlan`; retain them in canonical wire state and a companion presentation model. |
| Workout | Physical and logical IDs, local date/time zone, kind, title, purpose, minutes, planned meters, effort text, key/optional status. | `scheduledStartAt` is not mapped to native `scheduledMinutes`; estimated seconds are truncated to minutes. Strength instructions and other unused metadata are not surfaced. |
| Running | Ordered time-based segments; phase, title/cue, optional textual target and recognizable HR zone. | Distance-based completion is unsupported: a step with distance but no duration becomes `seconds = 0`. Pace upper bound and step distance are dropped; numeric RPE targets are not retained. HR bounds appear as text, but become a native zone only on an exact match to current personal zone boundaries. `stride` becomes generic work. Primary target type and run-level notes are not retained. |
| Repetition structure | Server grouped blocks are expanded in correct chronological order. | Block grouping and execution identity are lost; repeated steps after the first get freshly generated UUIDs during mapping. This cannot identify performed repetitions reproducibly. |
| Strength | Exercise prescription IDs/names/notes; sets with integer reps and integer target RIR; exercise-wide rest seconds. | Canonical exercise UUID is replaced by a name. Rep maximum, load kg, percent e1RM, RPE range, RIR maximum/fractions, set kind and per-set notes are dropped. Rest comes only from the first set. Superset grouping and substitution constraints/candidates are not represented. |

These are projection losses, not necessarily deletion from storage: `BackendReplica` retains the original wire records, and `movedPrescription` deliberately copies those records when moving sessions. New generation and new editing must not rebuild rich prescriptions from the reduced display model. [Mapping source](../ios/App/Models/Backend/BackendTrainingMapping.swift#L92), [wire-preserving move](../ios/App/Models/Backend/BackendTrainingWrites.swift#L158).

Tempo and duration-based resistance sets are not currently typed fields in either prescription schema. Add them only if the first release needs them, through explicit schema/capability extensions; putting them in notes does not make them executable.

### Required model changes

1. Add stable canonical exercise IDs to native prescriptions and logged sets. Keep display names separate. Introduce an executable prescription representation shared by phone and watch that retains the complete supported wire structure.
2. Represent a run step's completion condition explicitly: duration, distance, or an explicitly defined combination. Define elapsed versus active-time behavior, manual advance, pause handling, and GPS-unavailable behavior. Do not infer a duration from a pace target or silently skip unsupported steps.
3. Preserve run block/step IDs and repeat iteration as stable execution references. Include the plan version used when recording began. Use a deterministic execution key such as `(planVersionId, workoutId, stepId, repeatIteration)`.
4. Support strength ranges, set kind, load convention/target, per-set rest and targets, and substitutions before advertising those capabilities. Supersets must be rendered and recorded faithfully or excluded by the planner for that client version.
5. Keep citation references, rationale, provenance and change receipts adjacent to prescriptions. They must not contaminate set notes or execution parameters.
6. Retain raw canonical plans through all display/edit cycles; ordinary rescheduling and agent edits must preserve fields they do not change. Unsupported schema/capability versions must show a clear update requirement, never a plausible but incomplete workout.

### Catalog dependency

The backend catalog currently contains 28 UUID-addressed exercises and **no incline bench press variant**. iOS bundles 876 free-exercise-db entries addressed by string IDs, including several incline press variants. `exerciseID` currently performs case-insensitive name/alias matching and requires exactly one active result. [Server catalog](../server/src/catalog/data.ts#L40), [iOS catalog](../ios/App/Models/ExerciseCatalog.swift), [mapping](../ios/App/Models/Backend/BackendTrainingMapping.swift#L7).

Expand the canonical catalog, add stable source-ID mappings and aliases, and represent equipment constraints including adjustable/incline bench availability. A general `Bench` entry does not prove incline equipment exists. Resolve barbell versus dumbbell versus machine when the user has not made the intended variant clear; once selected, store its canonical ID. Never ask the model to invent an exercise UUID or treat all press variants as interchangeable.

## Detailed workout analysis: what exists and what is missing

The source of truth is performed activity, not the prescription. [WorkoutResult.swift](../ios/Shared/WorkoutResult.swift), [run uploader](../ios/App/Models/Backend/BackendTrainingMapping.swift#L134), and [server result schema](../server/src/workouts/schemas.ts) show three distinct levels of available data:

| Data | Phone/watch record today | Cloud upload today | Needed for detailed analysis |
| --- | --- | --- | --- |
| Run time and distance | Start/end, active elapsed time, total distance, time zone; pause-aware active counter. | Start/end and wall-clock elapsed duration, total meters. `movingDurationS` is not uploaded. | Preserve active and elapsed separately. Do not relabel active duration as moving duration without defining the measurement method. |
| HR | Most recent HR/time, mean and max; optional personal zone configuration. | Mean/max only. | Timestamped samples or verified bounded aggregates, coverage, sampling gaps, per-step HR and zone duration. Mean/max cannot reconstruct time in zones or HR drift. |
| Route and pace | Timestamped location/altitude/accuracy, segment breaks, last pace reading; route capped at 30,000 points. | No route or pace series. | Compute quality-aware split/interval/pace metrics; optional bounded on-demand samples. Raw coordinates are unnecessary for normal coaching. |
| Laps and intervals | Automatic kilometer/mile laps, manual laps, current interval offset. Laps have duration/distance, but not durable prescription-step execution events. | No laps/segments uploaded by this path. | Distinguish overlapping manual/automatic laps from non-overlapping execution intervals; preserve step ID/repetition/start offset. Never sum overlapping lap families. |
| Cadence, power, running dynamics | Not retained in `RunRecording` and not explicitly collected by this code. | Not sent. | Separate sensor/HealthKit collection work and capability flags. Mark absent fields unavailable; do not infer them. |
| Elevation | Route altitude is stored without a dedicated vertical-accuracy value. | Not sent. | Quality-aware ascent/descent computation and uncertainty; avoid claiming precise elevation or grade-adjusted performance from unqualified altitude samples. |
| Strength | Per-set reps, kg, completion boolean, optional integer RIR; prescription-set ID and exercise name. Session effort/notes and some timing. | Reps/kg/RIR and status, with all sets marked `working`, all loads `external`. Completed manual sessions currently save only checked sets. | Set kind, failed/omitted distinction, canonical exercise IDs, load convention, fractional RIR/RPE, timestamps/rest and explicit deviations; do not invent missing failures or rest. |
| Source and quality | Device source, native Health workout ID, GPS/recovery/Health-save messages locally. | `sourceType: manual` even for recorded runs. | Explicit first-party recording provenance versus imported HealthKit/manual entry; device/measurement source and coverage independent of the user-facing label. |

The backend already accepts moving duration, elevation, cadence, HR-zone totals and up to 500 run segments, but the current uploader does not populate them. New-device restoration reconstructs only a summary; the mapping retains a local `RunRecording` when one exists, but cannot restore an absent recording from current cloud data. [Local recording retention](../ios/App/Models/Backend/BackendTrainingMapping.swift#L65).

Introduce a versioned analysis packet bound to `workoutResultId`, `resultRevision`, `packetVersion` and content hash. Include observed session metrics, planned-versus-performed step/set comparisons, source/quality/coverage, user notes, training-date/time-zone basis, and which details are missing. The packet is evidence, not an instruction channel and not a replacement for canonical results. Keep exact route coordinates out of the default LLM context. Authorize optional data collection/upload separately through the existing account's AI consent and device permissions.

The user asks for substantial detail: keep bounded per-step/per-set measurements available to tools, not only a summary paragraph. Start with deterministic aggregates and allow the agent to request an identified interval or set range. Add bounded time-series chunks when recorded; do not send every GPS sample to every conversation. Claims about interval adherence, HR drift, fatigue, progression or recovery must state when coverage or the relevant measurement is missing.

## Typed application capabilities

Expose a registry of narrow, versioned commands. Each capability defines input/output JSON Schema, execution location, permission/foreground requirements, supported prescription versions, maximum payload, timeout, idempotency rules and whether it can mutate state. Backend authorization selects the tools offered to the model; a client manifest is compatibility information, not authority to grant itself tools.

| Capability family | Execution owner | Offline / foreground boundary | Mutation rule |
| --- | --- | --- | --- |
| Read athlete context, plans, catalog, results and evidence | Backend; iOS cache for local views | Cloud agent requires network; cached views remain available | Read only, authenticated athlete scope |
| Generate/validate a plan | Backend planner/compiler | Durable run continues when app is suspended | Complete validated draft; activate only within the user's expressed creation/replacement scope |
| Move/add/substitute/update future prescription | Backend domain service; local store consumes canonical sync | Existing manual offline edits remain queued; cloud commands wait for sync and current revisions | Explicit reversible edit may commit directly with an action receipt and Undo |
| Save preferences and agent memory | Backend canonical store | Optimistic UI may show pending; never claim saved before receipt | Explicit preferences are authoritative; inferred memory remains labeled and editable |
| Open plan, workout, analysis or preference screen | iOS navigation adapter | Foreground and installed destination | No domain write; use IDs, never arbitrary URL/script execution |
| Start/pause/resume/lap/finish a live workout | Owning phone/watch recorder | Local explicit action, device readiness and OS permissions; execution must survive loss of network | Pin active prescription snapshot; deduplicate command IDs; cloud model cannot independently initiate sensor recording |
| Log a performed set or manual result | Native form/store and canonical sync | Available offline with durable journal | Use explicitly supplied/recorded actuals and visible correction/undo; never convert planned values into completed activity |
| Collect extra Health/device details | Native adapter | Requires locally available data, OS permission and appropriate app execution state | Return typed, bounded evidence for a named result; never give the model general Health database access |
| Connect integrations, billing, deletion/export | Existing explicit product flows | OAuth/OS/payment/destructive actions require their existing user flows | Agent can navigate or explain; no broad background authority |

Not every capability must be enabled in the first release. Start with read, plan creation, future-plan edits, analysis and memory; add native live controls only after deterministic adapter tests. Do not make voice/cloud availability a prerequisite for recording.

An execution response must distinguish `completed`, `pending_sync`, `requires_foreground`, `requires_permission`, `unsupported`, `conflict` and `failed`. Tool-call selection or generated prose is never proof of successful execution. Server-issued device requests are account/device-bound, expiring and single-use; the device's replay receipt is durable before acknowledgement. A remote command targeting a different device must not quietly run on the currently connected phone.

## Direct edits and Undo

For “I would like to always do incline bench press,” the desired flow is:

1. Resolve the press variant against available equipment, current exercise and explicit preferences. Ask one narrow clarification only if the target/scope is materially ambiguous.
2. Record the explicit ongoing exercise preference with source message/run ID. Build a replacement of the relevant future press prescriptions, retaining completed and active sessions and unrelated exercises. Do not keep a flat-bench load automatically if it has no supported transfer to incline; use known incline history or a conservative effort target.
3. Validate the resulting plan and commit the preference plus new plan version atomically against expected active-plan/preference revisions. Return a receipt identifying exactly what changed, effective date and Undo availability.
4. Show “Updated your future press sessions to incline …” with affected sessions and an Undo action. Do not require an additional generic “Accept proposal” tap after an already explicit, scoped and reversible instruction.
5. Undo uses a compensating new version and restores the preference only if revisions still permit it. If subsequent unrelated edits exist, preserve them or ask about the precise conflict; never reactivate an old whole-plan snapshot that discards later work. Keep action and memory rollback linked.

For a full new block, show a complete draft and evidence by default. A clear “create and start” intent may authorize initial activation. Replacing an existing block or broad changes inferred from a vague complaint require a concrete scope before execution. This is a product behavior distinction, not a blanket extra confirmation requirement.

The current single-outbox design is a concurrency dependency. An agent edit cannot race a pending offline plan mutation and then be silently hidden by `hydrate()` preferring optimistic local state. Sync first or hold the cloud mutation and show the pending conflict. A recording that started offline is not necessarily visible to the backend; the device must keep its immutable start snapshot, and results must still link to that historical prescription after a newer plan activates.

## Run, event and memory integration

Proposed additive contract agreed for this planning document, subject to executable OpenAPI and cross-platform fixtures:

| Route / surface | Purpose |
| --- | --- |
| `POST /v1/agent/runs` | Start a durable run with intent `chat`, `create_plan`, `modify_plan` or `analyze_workout`; typed entity references, message/thread, device capability version and expected revisions; stable request/idempotency identity. |
| `GET /v1/agent/runs/{id}` | Recover authoritative run status and final result after timeout, app restart or lost response. |
| `GET /v1/agent/runs/{id}/events` | SSE with monotonic event sequence and `Last-Event-ID` replay. Store the event cursor separately from the canonical sync cursor. |
| `POST /v1/agent/runs/{id}/continue` | Typed clarification/authorization/device-result response to a server-issued single-use challenge; not an arbitrary tool execution endpoint. |
| `POST /v1/agent/runs/{id}/cancel` | Request cooperative cancellation; a committed action remains committed and requires Undo. |
| `POST /v1/agent/actions/{id}/undo` | Authorized compensating operation with revision checks and a new receipt. |
| `GET/PATCH/DELETE /v1/agent/memories` | Inspect, correct and forget personal memory, with typed item targeting, revision checks and audit provenance. Final item-addressing schema belongs in the main API contract. |
| `PUT /v1/workouts/{resultId}/analysis-input` | Idempotent versioned detailed workout packet with result revision and content hash. |
| `bootstrap.agentCapabilities` and device capability manifest | Negotiate server-enabled actions and supported executable prescription/packet versions. |

Existing `/v1/intelligence/chat` retains its current one-complete-event behavior during migration. Canonical plans, results and messages still restore through sync; SSE delivers progress and receipts, not an alternative database. New sync entity variants or message fields must be negotiated: current Swift decoding rejects unknown sync entity types and leaves the cursor unchanged.

Add a dedicated `AgentRunStore`/client adapter rather than running the provider inside `TrainingStore.askCoach`. Persist request identity before sending; recover by run ID instead of starting another provider call. Reconnect SSE with the last durably processed event, deduplicate by `(runId, sequence)`, and handle terminal snapshots, expired event history, authentication rotation, app suspension and account switching. The server continues durable cloud work while iOS reconnects later; do not design around a permanently open mobile connection. SSE is sufficient for current request/progress/response needs; bidirectional WebSockets are not necessary for the first release.

`CoachView` needs structured content types: prose, citation, plan summary, changed-session list, action receipt/Undo, analysis findings with metric evidence, clarification, tool progress, and visible failure/retry state. Streaming text is provisional; only a validated committed receipt may change the displayed active plan. Citations must open their actual registered source and show the claim/section they support.

For Hermes-inspired memory, separate a small stable athlete profile/preferences memory, retrievable conversation history, and bounded session summary. Version the stable memory snapshot per run so edits do not rewrite the prefix midway through a run. Reuse the same snapshot across compatible turns to preserve prompt-cache opportunities; caching implementation stays on the backend. Show “What your coach remembers” with source, scope, date, explicit/inferred status and edit/forget controls. “Always incline bench” is an explicit preference; a passing complaint should not become a permanent restriction automatically. Forget must affect future retrieval and summaries, not just remove a visible card. Account switch/logout must stop event listeners and clear the in-memory state of the previous athlete.

Scope guardrails and Jev policy checks belong on the backend, but the UI must represent refusals and clarification separately from network errors. Related pain or injury language needs a brief appropriate training-scoped response; it must not cause a fabricated diagnosis or a silent plan change.

## Validation and rollout dependencies

1. **Contract fixtures and catalog:** add supported capability versions, canonical incline variants/source mappings and representative plan/result fixtures. Generate Swift types from reviewed OpenAPI. No production model rollout before iOS can execute every enabled field.
2. **Executable model parity:** test time- and distance-ended runs, repeat ordering/identity, mixed targets, pace/HR ranges, stride phase, per-set rest/load/RIR, supersets, units and scheduled local times across DST. Bound expanded repetition counts and total execution steps so a valid but enormous plan cannot exhaust the device.
3. **Plan edits:** exact field preservation on an unrelated move, canonical UUID rather than display-name matching, apply-once response loss, plan changed during run, device started a workout offline, completed-result links, and atomic preference+plan Undo with later edits retained.
4. **Analysis evidence:** phone/watch run transfer, pause versus wall time, kilometer/mile/manual lap overlap, partial/no HR, unsupported cadence/power, sensor gaps, per-step matching, strength failed/skipped/bodyweight/assisted sets, packet hash/revision mismatch and account ownership. Verify claims cannot reference unavailable metrics.
5. **Agent UI recovery:** duplicate/out-of-order SSE, reconnect/replay, expired event history, app kill after server commit but before response, cancellation after commit, sync-outbox conflict, session expiry and account change. Each durable event is processed once; no failed run displays “plan updated.”
6. **Memory and citations:** edit/forget/retrieve, expired temporary preferences, corrections overriding stale memory, prompt-injection text in notes/history, provenance visibility, no invented citation or cross-athlete context, and accessibility/localization of all new cards.

Extend the existing [backend connection checks](../ios/Tests/BackendConnectionChecks.swift), [onboarding checks](../ios/Tests/BackendOnboardingChecks.swift), [run checks](../ios/Tests/RunWorkoutChecks.swift), [live metrics checks](../ios/Tests/RunLiveMetricsChecks.swift), and [training engine checks](../ios/Tests/TrainingEngineChecks.swift). Retain the existing durable journal and phone/watch receipt tests as regression coverage. Add shared JSON contract fixtures consumed by TypeScript and Swift rather than two independently written definitions.

The critical release sequence is: canonical schema/catalog → executable native parity → durable run/event adapter → generation/editing/Undo → richer recordings/analysis → memory polish and broader device tools. Recording, viewing existing plans and manual logging remain functional offline throughout.
