# iOS integration review of the AI architecture

Reviewed 2026-09-25 against repository `db10534`, following the [harness contract review](ai-ios-harness-review.md) and [AI implementation plan](ai-agent-implementation-plan.md).

This records the iOS implementation perspective after checking the current native models, mapping, sync, recorder, Watch transport and intelligence routes. The architecture is a suitable direction for implementation. Executable API contracts and release readiness remain subject to the gates below; this is not a scientific-policy or production-readiness approval. No application behavior or cloud AI has been enabled by this review.

## Architecture to carry forward

The backend owns the durable agent run, OpenRouter/provider access, evidence retrieval, memory, typed tool authorization, plan compilation/validation and atomic changes. iPhone and Watch own native permissions, executable workout presentation, actual recording and offline recovery. The model proposes structured operations; application services execute them.

Canonical sync remains the source of plans, results and restored conversation records. SSE communicates progress and receipts with its own durable event cursor. A model response, partial JSON, or stream event cannot independently install an active plan. Explicit scoped reversible edits may commit with a receipt and Undo; broad or ambiguous changes need resolved scope, not a blanket second confirmation.

The proposed `/v1/agent/*` and analysis-input routes are not implemented in the inspected code. Existing `/v1/intelligence/chat` returns one validated complete event, not a resumable agent stream. Keep that contract stable during migration. The current main tab view exposes Plan and Progress; the remaining local Coach code is not an integrated cloud feature. Add connected Coach behind its own capability/rollout gate rather than presenting local keyword responses as AI.

## Confirmed native prerequisites

| Area | Confirmed in current implementation | Required before enabling the affected feature |
| --- | --- | --- |
| Run execution | [Mapping](../ios/App/Models/Backend/BackendTrainingMapping.swift#L92) maps absent duration to zero, drops step distance and the upper pace bound, and allocates random IDs for later repeats. [RunTimeline](../ios/Shared/RunTimeline.swift) and the recorder advance by active seconds. | Typed completion conditions, complete targets, reproducible block/step/repetition references, bounded expansion, and matching phone/Watch execution. |
| Strength execution | [Native prescriptions](../ios/Shared/TrainingWorkout.swift) contain an exercise name, one rest duration, integer reps and integer target RIR. Rich wire fields are reduced during mapping. | Canonical exercise IDs, rep/effort ranges, load semantics, set kind and per-set rest. Supersets/substitutions must execute faithfully or remain outside advertised capabilities. |
| Cloud edits versus local edits | [Replica enqueue](../ios/App/Models/Backend/BackendReplica.swift#L33) permits one outstanding batch; [hydrate](../ios/App/Models/Connected/BackendAppController.swift#L168) prefers optimistic state while it is pending. | Reconcile the outbox before a cloud mutation, then check current server revisions. Preserve a visible pending/conflict state when reconciliation fails. |
| Recording and historical identity | [RunRecording](../ios/Shared/RunRecording.swift) embeds its workout snapshot. [Watch transfer](../ios/Shared/CompanionBridge.swift) uses durable files and receipts. | Retain these guarantees, add explicit plan-version/execution references, and accept late actuals against the original prescription after plan replacement. |
| Detailed analysis | Recording retains route/laps and HR summaries, but no complete HR series. [Result upload](../ios/App/Models/Backend/BackendTrainingMapping.swift#L134) omits laps/series and labels recorded runs manual. | Accurate first-party provenance, defined duration bases, coverage-aware aggregates and bounded revision-bound packets. Never reconstruct HR-zone time or drift from mean/max HR. |
| Catalog and conversation | Exercise resolution is name/alias based; the canonical catalog lacks incline variants. State hydration does not project server coach messages. | Stable catalog/source mappings and explicit conversation hydration, separate from transient run progress. |

## Additional migration details

**Cached projections need a version.** `BackendTrainingMapping.state` reuses a cached native plan when its ID matches ([line 82](../ios/App/Models/Backend/BackendTrainingMapping.swift#L82)). Merely fixing the mapper will not upgrade those cached plans. Introduce a projection-version migration that rebuilds eligible display/execution data from retained canonical records while preserving actuals, pending edits and immutable active-recording snapshots. Older recording/archive payloads must remain readable. Do not reset athlete data to perform this migration.

**Watch compatibility is independent of phone compatibility.** [CompanionSnapshot](../ios/Shared/CompanionSnapshot.swift) currently carries reduced workouts without an executable-schema version or explicit plan-version envelope. A capable phone does not establish that its paired Watch supports the same prescription. Freeze per-device version/capability negotiation, stale-manifest behavior and a clear unsupported-execution state. Never silently downgrade a rich prescription when forwarding it.

**Open intensity is not open-ended execution.** The [current server schema](../server/src/plans/schemas.ts) has `primaryTargetType: open`, but each step still requires duration or distance. That enum does not define a manual-ended step. Open completion and combined time/distance completion need explicit versioned semantics; do not infer them from a display label.

## Contract decisions to freeze with shared fixtures

| Decision | Required agreement |
| --- | --- |
| Completion and identity | Duration/distance/manual end conditions; what happens when both thresholds exist; pause, manual advance and unavailable GPS behavior; stable repeat references; supported limits and historical plan identity. |
| Lost start response | The client persists request identity before POST. Specify how the same request recovers the existing run when the response containing its run ID is lost: an idempotent POST replay returning that run, or an explicit request-ID lookup. `GET` by an unknown run ID alone cannot recover this case. |
| Receipts, cancellation and Undo | Typed terminal snapshots, action IDs, revision references, committed-before-cancel behavior and atomic plan/preference compensation. UI success follows a receipt and canonical state reconciliation. |
| SSE and sync compatibility | Event IDs/order, replay expiry and status fallback, auth/session changes, unknown-event policy and separate cursors. Negotiate new sync variants; older Swift decoders currently reject unknown entity discriminators. |
| Analysis input | Units and active/elapsed/moving definitions, overlap-safe lap families, historical zone configuration, missing-data reasons, packet version/hash canonicalization and revision invalidation. Packet limits/retention in the plan remain proposals. |
| Memory and device challenges | Item routes, expected revisions, edit/forget effects on cached sessions, and account/device-bound challenge expiry and replay receipts. A capability manifest is compatibility information, not authority. |

## First implementation slice

Start with Phase 0: executable contract parity and migration. Agree on shared TypeScript → Swift → Watch fixtures under `contracts/fixtures/ai/`, then regenerate wire types and implement the shared native execution representation. Use a mixed-duration/distance repeated run and a rich strength session as initial golden cases; test unsupported features explicitly rather than dropping them.

Acceptance must include canonical field preservation through an unrelated reschedule, repeat identity across restore, scheduled times across DST, phone/Watch version mismatch, cached-plan migration, paused/offline recording recovery and late actuals after activation. Existing [wire-preserving moves](../ios/App/Models/Backend/BackendTrainingWrites.swift#L158) should continue preserving untouched prescription values while allocating identities for a new immutable version.

Next, add the account/environment-scoped durable agent client and connected read-only Coach. Generation, direct edits/Undo, memory and detailed analysis then follow the phased rollout in the main plan. Device live-control tools remain later work; recording never depends on cloud availability. Four-language UI, accessibility and theme support apply to each new surface.

Validation for this review was documentation and source inspection only. No builds, live provider calls, health-data uploads or scientific-source revalidation were needed or performed. Training-policy applicability and model/cost benchmarks remain the separate review gates described in the implementation plan.
