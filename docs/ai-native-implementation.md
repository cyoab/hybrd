# Native AI integration — 25 September 2026

This is the native implementation companion to [the delivered agent API](agent-api.md). It supersedes the implementation-state observations in [the earlier iOS review](ai-ios-integration-review.md), not its future release gates. Backend work is owned by the parallel backend task.

## Delivered against the current backend

- Connected Coach tab with capability discovery, explicit cloud consent, read-only conversation and revision-bound workout analysis. No local keyword reply is presented as cloud AI. Apple Health permissions do not imply AI consent.
- Environment and API version flow through `BackendSession`; no model credentials or hard-coded backend hostname in Coach. The server continues to enforce policy, entitlement, quota, device registration and consent. Configuration defaults remain unchanged.
- `AgentRunStore` persists exact POST bytes and the UUID idempotency key **before** transmission. Atomic journals are segregated by origin, API version and athlete; excluded from backup and protected on iOS. Corrupt journals fail closed. No bearer tokens are stored in them.
- Lost POST responses replay the same request. SSE frames are bounded, UTF-8 decoded, validated against run/event identity and durably deduplicated. Their cursor is separate from sync. Canonical GET status restores terminal artifacts and bypasses expired event history. Stream failures fall back to bounded status/reconnect attempts. Indeterminate runs never create a new attempt automatically.
- Backgrounding/sign-out suspends listeners; identity is checked after awaits and before writes. Reopening Coach recovers the same run. Pending local training writes are reconciled before a new question or analysis. Revision conflicts leave the user in control.
- Known runs can be cancelled. **Unknown POST outcomes are not cancelled by issuing another POST**: that could create a new billable run. The UI asks the athlete to recover the existing request first. A lookup/cancel-by-idempotency-key endpoint is needed to remove this contract limitation.
- Structured content, measured observations, interpretations, limitations, recommendations, and HTTPS registry citations are displayed separately. Corrected/deleted analysis sources are labelled historical when `artifactStale` is returned. On reopening Coach the latest 50 local analyses are revalidated. Older transcript history remains accessible through canonical sync; rich artifact restoration on a fresh installation needs an artifact/run listing or message-to-run reference in the backend contract.
- User-authored memory supports create, edit, expiry, revision-aware deletion and conflict recovery. Forgetting does not claim to delete historical transcripts or workouts. There is no automatic extraction.
- English, Spanish, Brazilian Portuguese and French UI strings; semantic text sizes, native controls, dark/light colors and VoiceOver labels.

## Executable prescription foundation

Canonical plans are reprojected from their complete wire records rather than retaining an obsolete cached display projection. Active drafts and recordings retain their own immutable workout snapshot. Scheduled local time, exact estimated seconds, instructions, run-level notes, target type, strength focus, exercise IDs, superset groups, substitutions and per-set targets survive mapping and Watch encoding.

Version 2 execution expands repeats with deterministic IDs derived from block ID, step ID and zero-based iteration. Targets preserve distance, duration, both pace/HR/RPE bounds, rep ranges, load kg/percentage, RPE/RIR ranges (including fractions), set kind, rest and notes. Expansion is bounded before allocating arrays.

A run step ends on its single duration or distance target. Time does not invent distance when GPS is unavailable. Boundaries record observed active time and cumulative distance; pauses exclude idle time. Manual advance records a separate reason without adding actual time/meters. Interrupted/finished steps retain measured partial work. Manual laps remain separate. Rich strength targets are visible per set, supersets advance to the next unfinished group member, and actual fractional RIR/load convention/catalog identity survive result upload. Assisted/bodyweight loads are excluded from external-load PR comparisons.

Unsupported combined time+distance end conditions and newer execution versions are visibly blocked. Version 1 `primaryTargetType:open` is an intensity target, not an open-ended step. Optimistic plan moves must sync their canonical IDs before starting; existing active sessions stay pinned. Substitution alternatives are retained but interactive substitution execution is not advertised.

Watch transport publishes the complete versioned snapshot under `executableSnapshotV2`; the legacy `snapshot` key excludes rich workouts so an old Watch cannot silently execute a reduced prescription. New Watch versions accept old snapshots. This is compatibility protection, **not a server-registered paired-Watch capability manifest**. Explicit device negotiation and a paired-Watch update explanation remain prerequisites for AI-generated plan rollout.

## Shared fixtures and verification

`contracts/fixtures/ai/mixed-run.json` and `rich-strength.json` are synthetic canonical `PlannedWorkoutInput` examples. The mixed run includes DST-local scheduling, repeated time/distance steps, non-integer pace/RPE and strides. The strength fixture includes warm-up/working/backoff sets, fractional RIR, percentage load, superset identity and an alternative exercise.

`mixed-run-execution-ids.json` freezes deterministic phone/Watch identity. The derivation hashes UTF-8 `hybrd.run-step.v1|UPPERCASE_BLOCK_UUID|UPPERCASE_STEP_UUID|ZERO_BASED_ITERATION`, takes 16 SHA-256 bytes and sets UUID version/variant bits; this is a project-specific deterministic ID, not standard UUID-v5/SHA-1.

Run:

```sh
bun contracts/fixtures/ai/validate.ts
bash ios/Scripts/check-core.sh
python3 ios/Scripts/generate-onboarding-wire.py --check
python3 ios/Scripts/check-localization.py
```

The native suite uses an injected HTTP transport and synthetic fixtures. It verifies journal-before-send, exact replay after a lost response/relaunch, account/API isolation, bigint cursors, cancellation without unexpected work, bounded fragmented SSE, canonical fixture decoding, Watch roundtrip, pause/GPS/manual-advance behavior, pinned snapshots and fractional strength actuals. Fixtures also passed the server's `PlannedWorkoutInput` validator. Both iPhone and Watch build using Bitrig.

Live provider quality, actual SSE network behavior under device suspension, physical Watch GPS/HealthKit recording, and product UI testing with an entitled account still require integration/beta validation. Automated checks do not establish physiological or scientific accuracy.

## Remaining backend contracts before future feature activation

1. **Create/modify/Undo:** typed blueprint/artifact/action receipts, revision conflicts, durable recovery, scoped approval and undo expiry. Current capability values are literally false and unsupported operations are not offered.
2. **Execution negotiation:** registered phone/Watch schema/features, negotiated limits and paired Watch freshness. Explicit semantics for combined/open completion, substitution execution and unsupported envelopes. Current sample expansion limit is 2,000 steps; result segments currently cap at 500, so agree on a compatible upload/coverage strategy.
3. **Detailed analysis/provenance:** an account/result/revision-bound bounded packet and source enum distinguishing first-party iPhone/Watch, HealthKit imports and manual entry. Current v1 result writes have only `manual`/`healthkit`; native recordings preserve precise source locally and retain the existing server mapping rather than invent an enum. Agree on active/elapsed/moving duration, actual interval/lap identities, completion reasons, HR coverage/sampling and omission reasons before exporting traces. No GPS route is sent to the model. Native mean/max HR is not converted into invented HR-zone time, drift or per-step HR.
4. **Recovery/discovery:** lookup/cancel by request idempotency key, list runs or reference run IDs from messages to restore rich artifacts across devices, and an explicit OpenAPI component for the SSE event payload (currently documented, decoded strictly in `AgentStreamEvent`).
5. **Evaluation:** deterministic invalid-plan fixtures plus model/provider evaluations, citation claim checks and device measurement comparison before production rollout. Existing `intelligence/chat` remains unchanged.
