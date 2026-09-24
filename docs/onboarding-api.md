# Connected onboarding API

Implemented 24 September 2026 from [the iOS brief](onboarding-backend-handoff.md). This is the backend contract; the native preview still needs its authenticated adapter, Health reads, review UI, local planner and purchase integration. [OpenAPI](../contracts/openapi.yaml) defines every request/response type. A complete manual request is checked in as [onboarding-draft.json](../contracts/examples/onboarding-draft.json) and validated by tests.

## Integration sequence

1. Authenticate through existing email OTP/Apple/Google; use the hybrd bearer session. Bootstrap, register the installation, restore canonical data with pull/ack, then **always call `GET /v1/onboarding`**. Bootstrap's shape is unchanged. An offline completed athlete should retain their existing local training state.
2. For `not_started`, review any anonymous draft before attaching it to this account. For `draft`, restore its revision and semantic step. For `completed`, use the receipt and its selected membership to resume purchase/plan acceptance. Local preview flags do not override server state.
3. Offer Health and Strava independently. Health is read and normalized on the phone. Start Strava with `POST /v1/integrations/strava/connect {"autoPublish":false}`; the existing default when omitted remains true for compatibility. Request no publishing permission during onboarding. Fetch authenticated connection status after the OAuth return.
4. Save reviewed answers with `PUT /v1/onboarding/draft`. Keep null for unanswered optional/scalar values; use the exact typed fields, canonical units and stable enums, never localized UI labels. Save `baseRevision:null` only for the first draft; every later save uses the last returned revision. Each distinct request needs a new UUID `Idempotency-Key`. Persist the key and body together until the request succeeds.
5. On the editable recap, finalize the exact saved revision with `POST /v1/onboarding/complete`. Completion is a single database transaction over the normal canonical repositories, with ownership checks and sync events. It makes no provider calls, grants no subscription, generates no plan and activates no plan.
6. Pull from the installation's existing cursor and acknowledge normally. The receipt's `latestSequence` is only a catch-up hint, never a safe replacement cursor. Prepare the candidate locally; purchase/restore through StoreKit and submit/activate a plan through the existing explicit acceptance flow.

All three routes require auth but no entitlement. They use JSON over HTTP; no WebSocket/SSE is necessary. Poll Strava status while an import is pending, backing off to `retryAfterSeconds`; do not turn a timer or percentage animation into a success signal. Existing LLM transport is described in [the iOS integration guide](ios-handoff.md).

## Routes, revisions and recovery

| Route | Body / result |
| --- | --- |
| `GET /v1/onboarding` | `{schemaVersion:1,status,draft,draftRevision,step,completion,reviewIssues}`. Status is `not_started`, `draft`, or `completed`. A completed response clears the working draft and returns the durable receipt. |
| `PUT /v1/onboarding/draft` | `{baseRevision,step,draft}` → `{draftRevision}`. Full replacement, not a JSON patch. UUID `Idempotency-Key` required. Revision strings are decimal integers. |
| `POST /v1/onboarding/complete` | `{draftRevision,deviceId,catalogVersion,policyVersionId}` → `OnboardingCompletionReceipt`. UUID `Idempotency-Key` required. Use the current catalog version and an available published/retired policy UUID. |

Semantic steps: `connections`, `identity`, `goals`, `baseline`, `body`, `schedule`, `equipment`, `focus`, `readiness`, `review`, `preparing`, `membership`. They are navigation hints, not validation bypasses or prototype screen numbers. `schemaVersion:1` versions the draft/details/zone DTOs independently of `/v1` and catalog/policy versions.

A receipt contains `submissionId` (the completion key), completion time, reviewed draft revision, catalog/policy versions, named athlete-details/baseline/context references, every saved entity ID/revision, the sync hint, planning support, and `choices` (Health/Strava intent and selected membership). Choices grant no permissions or access. Normal pull restores profile/details, preferences, goals, availability, equipment, baseline and immutable context. The context also pins the reviewed details snapshot/revision. Preferred name is distinct from the auth display name; it never changes identity/email or merges accounts.

A successful replay returns its stored outcome **before** checking expired imports or the now-completed state. Idempotency is scoped by authenticated athlete and route and bound to a canonical payload hash. Same key/different content returns 409. A second completion key cannot overwrite the receipt; recover it with GET. A draft replay returns its original revision, so use GET if subsequent edits may exist. Two devices saving the same base revision get one success and one conflict. A profile changed by normal sync after the last draft save also requires another review/save before completion.

Existing training setup without an onboarding receipt is protected: completion returns `ONBOARDING_EXISTING_SETUP`; restore and edit existing canonical data through explicit profile/replan flows. It never manufactures a completion receipt for an older account or replaces an existing plan.

## Canonical answers

Required at completion: profile settings, preferred name, both goals, priority, both experience levels, weekly running distance (including zero), current lifting frequency (including zero), baseline period, at least two available weekdays, desired lifting frequency, session length, confirmed equipment, focus set, and readiness. Drafts may leave these unanswered. Body facts, race date, zones, records, context, connection intent and selected membership are optional.

| Input | Mapping / validation |
| --- | --- |
| `details.preferredName` | Trimmed 1–40 characters. Canonical `athlete_details` entity uses the athlete UUID. |
| `profile` | Existing timezone, locale, distance `km/mi`, load `kg/lb`, weekday and separately reviewed cloud-AI consent. |
| `details.heightUnit` | `cm/ft_in`; values remain canonical cm. |
| `details.age` or `dateOfBirth` | `{years:1…120 integer,asOf:"YYYY-MM-DD"}` or actual DOB, never both. No fabricated DOB. |
| Weight / height | Nullable 20–400 kg / 80–250 cm; retain decimal precision. No clamping. |
| Experience | Separate `new/beginner/intermediate/advanced` values in preferences' typed `onboarding` extension. Existing single experience remains null for this flow. |
| Running goal | `fitness/5k/10k/half_marathon/marathon` → `general_fitness` or `race`, with 5,000 / 10,000 / 21,097 / 42,195 meters. Optional race date remains a calendar date. |
| Strength goal | `strength/hypertrophy/maintenance` → explicit goal plus strength objective. Native build/muscle/maintain maps accordingly. |
| Priority | `balanced/run_first/strength_first`. Policy-owned run weights 0.50/0.65/0.35; strength is the remainder. Custom values are not onboarding choices. |
| `weeklyDistanceM` | 0–250,000 meters, retaining fractional precision across unit conversions. Baseline scalar key `weeklyDistanceM`, alongside `onboardingMetricsVersion:1`. |
| Current lifting | `currentStrengthSessionsPerWeek`: 0–7, fractional allowed (10 sessions/4 weeks = 2.5). **Native must extend its integer model or request an edited representative routine.** No silent rounding. |
| Desired lifting | `desiredStrengthSessionsPerWeek`: integer 1–4 and at most available weekdays. Stored separately in preferences/context. |
| Weekdays | **Foundation convention everywhere in this contract: Sunday=1, Monday=2, Tuesday=3, Wednesday=4, Thursday=5, Friday=6, Saturday=7**, including `weekStartsOn`. Each selected day permits one session; unselected days permit zero. No implicit two-a-days. |
| Session length | 30/45/60/75/90 minutes. |
| Equipment | Catalog UUIDs. `equipmentConfirmed:true` + empty array explicitly means bodyweight-only; false means unanswered. |
| Focus | Catalog muscle UUIDs; empty set explicitly means balanced focus. |
| Readiness / context | `ready/returning/adjusting`; nullable note ≤300 characters. Neither is a diagnosis or AI consent. |

Policy schema adds optional `onboarding.priorityWeights`, `minimumWeeklyDistanceM`, and `maximumWeeklyDistanceM`; policies published before this addition use the documented legacy interpretation above. The development policy is now version 3. The current local planner range is 3,000–150,000 m/week. Completion **still succeeds** outside it, preserving the answer, with `planning.status:"unsupported_baseline"` and `reason:"weekly_distance_outside_planner_range"`. Inside it, status is `ready_for_local_planner`, which is not a promise of successful candidate generation.

`baselinePeriod` uses dates. For unedited imported baseline metrics it must match the reviewed 28-day window's start/end date strings; exact instants/timezone are retained in provenance. The rolling Strava window uses UTC; the broader 365-day import is distinct. For manual answers supply the actual recent reference period. Calendar fields are not midnight UTC timestamps. Numeric JSON is independent of locale.

Zones are `schemaVersion:1`, configuration `custom/default/system/unknown`, and exactly five contiguous increasing ranges. Bounds are bpm, allow fractional precision, and only the last maximum may be null (unbounded). Bounds must be within 0–300; no rounding to four integer starts. A provider preview with an incompatible layout remains visible but cannot be accepted unchanged. Use an explicit reviewed edit/manual fallback. No max/resting/threshold HR is inferred.

Running records contain distance in meters, integer elapsed seconds, nullable performed date, and `athlete_reported/observed_effort`. Strength records contain canonical exercise UUID, kg, reps, nullable date and `athlete_reported`. Each list is bounded to 30. Import provenance applies to the selected list; Strava observed efforts must match the preview and stay `observed_effort`. There is no assertion of verified all-time PRs. Unknown exercise IDs are rejected; the existing native exercise catalog still needs explicit UUID mapping.

## Catalog mapping

Catalog version **2** retains all existing UUID meanings and adds the missing offered equipment. Fetch `/v1/catalog` and resolve these slugs to its UUIDs. Do not send Swift raw values as IDs or silently drop an option.

| Native option | Catalog slug |
| --- | --- |
| dumbbells | dumbbells |
| barbell | barbell |
| kettlebell | kettlebell |
| ezBar | ez-curl-bar |
| plates | weight-plates |
| bench | bench |
| rack | rack |
| pullUpBar | pull-up-bar |
| cableMachine | cable-machine |
| legPress | leg-press |
| legExtension | leg-extension |
| legCurl | leg-curl |
| chestPress | chest-press |
| latPulldown | lat-pulldown |
| seatedRow | seated-row |
| smithMachine | smith-machine |
| bands | resistance-band |
| medicineBall | medicine-ball |
| stabilityBall | stability-ball |
| foamRoll | foam-roller |

All ten native focus raw values match muscle slugs: `chest`, `back`, `shoulders`, `biceps`, `triceps`, `core`, `quadriceps`, `hamstrings`, `glutes`, `calves`. Muscle/equipment UUIDs are separate namespaces. Newly added equipment does not imply the small server exercise catalog contains every native exercise for that machine.

## Import review and retention

Strava status now adds nullable `onboardingPreview` beside the compatible `history`. The preview has UUID `id`, decimal `revision`, `generatedAt`, fixed seven-day `expiresAt`, and independent `profile`, `heartRateZones`, `runningHistory` sections. Each section has `pending/ready/unavailable/failed`, nullable reason, data, source, fetch time, retry delay and coverage. Stable reasons include `scope_missing`, `not_provided`, `history_partial`, `no_activities`, `rate_limited`, `provider_unavailable`, `preview_expired`, `not_supported`, `invalid_value`; not every reason is emitted by every section.

Profile uses the [authenticated athlete endpoint](https://developers.strava.com/docs/reference/#api-Athletes-getLoggedInAthlete), accepts name independently from weight, and never supplies age/height or a fabricated weight measurement date. Basic `read` can yield name; weight/zones require `profile:read_all`. Activity-only grants can yield history; profile-only grants can yield profile/zones. Actual provider denial remains authoritative. The existing `/history` refresh route refreshes these independent sections too. `history.strengthWindows` is additive and exposes 7/28/365-day sessions and exact sessions/week; do not substitute yearly `strengthSessions` for recent frequency.

History reuses the existing bounded calculation: up to 2,000 summaries/365 days, flagged/out-of-window exclusion, ID deduplication, moving-pace aggregates and sampled best efforts. `activity:read` coverage is partial because private activities may be omitted. No activity records means no recorded activity in this import, not proof of no training. Volume uses the entire 28-day interval: 280,000 m × 7/28 = 70,000 m/week.

Each `importDecisions` entry chooses one source/action per field:

```json
{"field":"weightKg","source":"strava","decision":"accept","previewId":"<UUID>","previewRevision":"3"}
```

Health uses `{field,source:"healthkit",decision,batchId,sourceIds,observation}`. Observation includes nullable `measuredAt`, `fetchedAt`, nullable `{start,end,timezone}` window, coverage (`complete_returned_records/partial/unknown/sampled_runs_within_period`), nullable duration basis (`moving/active/elapsed`) and `calculationVersion:1`. Baseline metrics need an exact 28-day window. Only reviewed facts/compact summaries and ≤100 source IDs per decision are sent; no routes or raw sample arrays. Health name/exercise-level lifting records are not supported imports in this version. Health provenance is explicitly `client_reported`, not server-verified Health permission.

The server resolves Strava `accept` against its owned, current preview and compares the submitted value. `edit` retains the valid athlete override and sets `editedFromSource:true`; `reject` applies no provider provenance. A manual value needs no import decision. The field `runningRecords` accepts the preview's whole observed-effort list; selecting/editing a subset uses `edit`. Canonical provenance is server-managed, includes measurement/fetch/window/coverage/review metadata, and normal details edits retain it only on unchanged facts.

Only one source/decision may be selected per field. Do not sum Health and Strava totals. Select one history source per metric/window; body/zones can come from another. Manual changes and reviewed values must never be replaced by a late import. An optional best-effort fetch can advance the preview revision; review that new revision explicitly rather than automatically updating the decision's number.

Draft storage keeps Strava `accept` references, not duplicated imported values. GET hydrates only a still-valid exact snapshot; stale references return null/empty values plus `reviewIssues`. Edited values remain athlete overrides. Reconnect, refresh, webhook invalidation, disconnect and expiration invalidate unaccepted snapshot references; completion returns a recoverable conflict. Reviewed canonical facts/baselines retain their provenance under the existing retention policy. Draft idempotency outcomes contain only revisions; completion outcomes contain references/receipt, no copied preview. Expired preview and temporary history payload cleanup runs even with provider credentials disabled. Account deletion cascades drafts, request receipts, details and provenance. Export includes canonical records and the account's resumable onboarding state, never tokens.

## Error handling and testing

Domain errors use `{error:{code,message,details?:{fields:[...]},requestId}}` and `X-Request-Id`. `400 VALIDATION_ERROR` means the JSON/header schema is invalid. Completion domain validation uses 422; conflicts use 409. Auth expiry is 401; unregistered/revoked device is 403. Do not interpret a service failure as saved setup.

| Code | Native response |
| --- | --- |
| `ONBOARDING_REVISION_CONFLICT` | GET, merge/review changes, save against the returned revision, use a new request key. |
| `IMPORT_PREVIEW_EXPIRED` / `IMPORT_REVIEW_REQUIRED` | Fetch status, review a current suggestion or replace/remove the import decision with a manual answer. Preserve unrelated answers. |
| `UNSUPPORTED_CATALOG_MAPPING` | Refresh catalog and resolve the indicated IDs/version. |
| `ONBOARDING_VALIDATION_FAILED` | Highlight `details.fields`; preserve the draft and correct it. |
| `IDEMPOTENCY_KEY_REUSED` | Keep each durable request key bound to its original payload; new content needs a new key. |
| `ONBOARDING_ALREADY_COMPLETED` | Recover the receipt with GET; subsequent changes use normal sync/profile flows. |
| `ONBOARDING_EXISTING_SETUP` | Restore the older canonical setup and use explicit edits/replanning. |

Backend automated coverage includes manual/Health/Strava/mixed completion, all weekdays, fractional zones/frequency, profile-only/activity-only grants, missing profile weight, provider failure/429, 70 km/week math, review ownership/expiry, concurrent saves/completion, replay after disconnect, transaction rollback, full restore/export and account deletion. Run `make check`; `make up` applies migration 0006 and seeds development catalog/policy. Only API and PostgreSQL are required long-running dev containers; the worker runs inside API. Tests inject providers and send no real email or provider requests.

Native acceptance still needs a consented test account with configured Resend/social auth, Strava credentials/callback/app link, real Health permissions, catalog adapters, local plan acceptance, and StoreKit. Do not upload disconnected sample plans/workouts or attach another account's draft automatically.
