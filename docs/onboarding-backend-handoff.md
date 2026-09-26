# Onboarding → backend handoff

Original iOS implementation brief, 23 September 2026. **Backend implementation delivered 24 September 2026:** draft/read/atomic-completion endpoints, typed athlete details, catalog mappings, independent Strava previews, restore and provider fixtures are implemented. See [the implemented API contract and native integration decisions](onboarding-api.md) and [OpenAPI](../contracts/openapi.yaml). The original requirements and “Backend today” assessment below describe the pre-implementation state; they are retained as the acceptance brief. Native connected onboarding is still to be integrated; this does not mark the disconnected iOS prototype as connected.

## Outcome and decisions

Onboarding should **auto-fill as much relevant information as possible from Apple Health, Strava, or both**, then ask the athlete to review it and answer only what is missing or subjective. Offer both connections early, before body and training-baseline questions; neither requires connecting the other. Connection is part of setup, not a promise to connect later. Keep a manual route for unavailable services, missing data, and people who choose not to connect.

The current iOS journey remains a disconnected prototype until native integration is implemented. This document does not authorize background uploads of existing sample plans, local workouts, or onboarding drafts. Applying a draft to an authenticated athlete requires the athlete's review.

Implementation decisions for the next phase:

- Authenticate the hybrd account before starting Strava OAuth. Strava is an attached training source, **not a hybrd sign-in provider**. Reuse the existing auth/session and connection routes.
- Request read access for onboarding. Send `autoPublish:false` explicitly; workout publishing is a separate opt-in. The current connect schema defaults to `true` when omitted.
- Prefill untouched answers from available, valid imported data, with source/date labels and a review action. Do not make athletes retype known values or revisit fully answered forms. Confirmation can happen on one editable recap; conflicting, stale, or uncertain values need focused review. Never overwrite an edited or confirmed answer when a background import finishes.
- Use Apple Health and Strava as complementary sources. Resolve each field independently; an unavailable source must not block the other. Import observations, not invented goals or experience levels.
- Use the last 28 days to suggest recent weekly running volume; show its period and coverage. Keep goals, availability, equipment, focus muscles, and experience as athlete answers.
- Persist the reviewed setup independently of purchase. Membership selection, verified entitlement, a saved profile, and an activated plan are separate states.
- Keep plan candidate generation in the existing local iOS engine. The server validates, persists, and activates plans; this brief does not introduce server-side plan generation.

## What Strava can supply

The documented athlete model exposes name and weight, but **does not expose height or date of birth/age**. HR settings come from a separate endpoint. Do not advertise a complete body profile import. These capabilities were checked against the [Strava athlete model](https://developers.strava.com/docs/reference/#api-models-DetailedAthlete) and [athlete/zone endpoints](https://developers.strava.com/docs/reference/#api-Athletes-getLoggedInAthleteZones).

| Desired information | Import/review behavior | Backend today |
| --- | --- | --- |
| Preferred name | Suggest the first name from `/api/v3/athlete`; allow editing. Do not replace an existing preferred name. | Missing. OAuth parsing retains only the remote athlete ID; no athlete profile fetch is implemented. |
| Weight | Suggest a valid returned weight in kg, with fetch time and unknown measurement date; it may be absent or outdated. | Missing from provider adapter and preview DTO. |
| Height | Manual cm or feet/inches; optionally Apple Health. | No Strava source. Needs a canonical profile field. |
| Age | Optional manual age or separately authorized Health data. Never derive it from Strava account creation time. | No Strava source. Needs a canonical profile field. |
| HR zones | Review configured zones from `/api/v3/athlete/zones`, retaining custom/default provenance. | Implemented in `history.heartRateZones`; rich canonical profile storage still missing. |
| Recent running volume | Use the imported 28-day window's `averageWeeklyDistanceM`, not a prescribed target. | Implemented alongside 7- and 365-day windows. |
| Running frequency, pace, longest run | Explain these as observations from imported activity history. | Implemented. Pace is a moving-pace aggregate, not a race prediction or prescribed pace. |
| Running records | Offer returned efforts as observed best efforts with dates and coverage, not guaranteed all-time PRs. | Implemented as a bounded sample of runs within the imported year. |
| Lifting frequency | Suggest recent frequency from appropriately classified workouts, then confirm it represents the athlete's current routine. A yearly count is insufficient. | `strengthSessions` counts the full import period; add a recent-window calculation for this suggestion. |
| Lifting records, experience, goals, schedule, equipment, muscle priorities | Athlete input. Do not infer strength level or sets/reps/load from a WeightTraining activity. | No complete source in the existing import. |

## Apple Health is a primary import path

Apple Health reads run on iPhone, after the athlete chooses to share the relevant data. Reuse the existing `HealthProfileReader` and review behavior: today it imports DOB, latest weight and height for the athlete profile. It is **not yet connected to onboarding**, and does not read workout history or zone settings. Extend it through a dedicated onboarding import adapter rather than duplicating profile conversion logic.

| Information | Apple Health contribution | Review / limitation |
| --- | --- | --- |
| Age / date of birth | Read the shared date-of-birth characteristic and derive current age for display. | Preserve the actual date; do not invent DOB from an entered age. |
| Weight and height | Latest valid body-mass and height samples, with measurement dates. | Prefer a recent dated measurement over an undated suggestion; let the athlete resolve conflicts and stale readings. |
| Running volume and frequency | Query running workouts within the same bounded 7/28/365-day windows; use associated workout distance. | Daily walking/running distance also includes walking and must not become training mileage. Missing workout distance is unknown, not zero. |
| Running pace and longest run | Use valid running-workout distances and durations, with the duration basis recorded. | Health workout active duration is not automatically equivalent to Strava moving time; label it accurately and compare only like metrics. |
| Current lifting frequency | Count appropriate traditional/functional strength workouts in the recent 28-day window. | Suggest recorded sessions/week and ask whether this reflects lifting; generic workouts may not be lifting, and sessions are not necessarily distinct days. |
| HR zones | On iOS 27, read `HKHealthStore.preferredWorkoutZoneConfiguration(for:)` for heart rate. | Preserve system/user source and exact boundaries. Use Strava or manual values when the API/data is unavailable. |
| Running records | Derive observed efforts only when sufficient workout/segment data supports the distance and duration. | A workout's average pace does not prove a faster-distance PR. Keep candidates attributed and reviewable. |
| Name | Use Strava or a name explicitly supplied by the sign-in provider, if available. | Do not promise a HealthKit name field. Keep preferred-name editing. |
| Exercise-level lifting PRs, experience, goals, equipment, muscle priorities and future schedule | Keep explicit athlete answers unless a supported source actually supplies the fact. | A strength workout summary does not establish exercise, weight, reps, RIR, or lifting ability. |

Apple references: [height](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/height), [body mass](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodymass), [date of birth](https://developer.apple.com/documentation/healthkit/hkhealthstore/dateofbirthcomponents()), [workout data](https://developer.apple.com/documentation/healthkit/hkworkout), and [active workout duration](https://developer.apple.com/documentation/healthkit/hkworkout/duration).

The installed iOS 27 SDK declares `preferredWorkoutZoneConfiguration(for:)` as available from OS 27. Guard it with `if #available(iOS 27.0, *)`; shared Watch code needs the corresponding watchOS guard. The app's older deployment target must retain a working fallback. Read the preferred configuration, not an arbitrary old workout's app-defined zones. Health boundaries can be fractional and open-ended, so preserve precision in the new typed contract and update the native integer-only zone model deliberately. See [preferred zones](https://developer.apple.com/documentation/healthkit/hkhealthstore/preferredworkoutzoneconfiguration(for:)) and [zone data/source semantics](https://developer.apple.com/documentation/healthkit/accessing-workout-zone-data).

Request only data types used by onboarding: DOB, height, body mass, workouts, workout distance and heart rate for the selected import features. No Health writes or GPS routes are required to fill these fields. A preference toggle or completed authorization request does not establish that data was shared. HealthKit deliberately does not expose whether read permission was denied: show “No shared data available” when appropriate, not an asserted denial or zero training volume. [Apple authorization behavior](https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:)).

### Health import contract and ownership

There is no backend OAuth connection to Apple Health. iOS queries and normalizes shared data locally; the backend stores the athlete-reviewed canonical fields and bounded baseline summaries through the proposed draft/completion routes.

- Add a source-neutral import candidate type on iOS: field key, canonical value/unit, `healthkit | strava`, source identifier, observation/measurement time (nullable), fetch time, window, coverage, and review decision. Use source-specific references: a server preview ID/revision for Strava; a local import batch ID and relevant sample/workout identities for Health. Do not require a Strava preview ID for Health-only completion.
- Keep unreviewed Health candidates local. Save accepted values after the athlete reviews what will be applied to their account. The server validates types, ranges, ownership of the draft and supported calculation versions; client-reported Health provenance is not server-verified access to HealthKit.
- Preserve measurement dates, metric duration basis, aggregation version and observed coverage in typed metadata. A completed Health query means it processed returned records, not that every real workout or every Health record was shared.
- Upload only the accepted profile facts, compact summaries and source references needed for this setup. Bulk raw samples, routes and full workout history are a separate sync scope, not a prerequisite for onboarding. Do not misuse the existing workout `activity_source_record` as body-profile storage.
- Run Health and Strava imports independently. Render available fields progressively, cancel local queries when appropriate, and retain a reviewed draft across interruptions. Revoked/unavailable reads must not erase already reviewed answers.

## Recommended connected journey

This changes the order of the production journey; do not bind the backend contract to prototype step numbers.

1. **Create account / sign in.** Use configured email OTP, Apple, or Google. Successful auth already creates/restores the athlete. Store the hybrd session in Keychain; bootstrap, register the installation, and restore account data before attaching a local draft. Existing accounts resume their setup instead of overwriting their profile.
2. **Fill your starting point automatically.** Offer Apple Health and Strava with clear explanations of what each can supply. Let the athlete use either, both, or continue manually. Request separate permissions and start the available imports independently.
3. **Review quick suggestions.** Prefill name/body details/zones as each source becomes available, independently of longer history queries. Skip redundant input forms when valid data already fills them, while retaining editing in the recap. Keep navigating during imports; show pending/partial states. A late result produces a review action instead of overwriting an answer.
4. **Goals and starting point.** Ask for both disciplines' goals, balance and separate experience levels. Confirm the imported mileage and recent lifting-frequency suggestions if present; ask for manual values only where missing, unrepresentative, or incompatible with the input model.
5. **Life and training preferences.** Capture body details if desired, weekdays, desired lifting frequency, time per session, gym equipment, focus muscles, readiness, and an optional context note.
6. **Review your starting point.** Show every selected value, its source where relevant, missing optional fields, and any partial-history warning. Let the athlete accept, edit, or reject each import. Include HR zones and observed efforts here; they are not currently fields in `OnboardingDraft`.
7. **Build my plan.** Persist the reviewed setup reliably and start local candidate preparation. Retain the four-second visual sequence, but do not use its timer as a backend success signal. If saving/preparation takes longer, show a truthful waiting/retry state; preserve answers on failure. Account creation has already happened, so do not claim to be creating it again.
8. **Membership.** Present monthly/annual products. The current USD prototype is $10.99/month or $99.99/year, with “Get 2 months free” as an annual comparison, not a free trial. Production prices come from StoreKit. A canceled/pending purchase must not erase the athlete's setup.
9. **Enter training.** Use verified access and explicit plan acceptance/activation. Recover an interrupted purchase or activation without duplicating an account, baseline, subscription, or plan.

## Existing endpoints to reuse

The authoritative current wire contract is [contracts/openapi.yaml](../contracts/openapi.yaml). See [iOS integration](ios-handoff.md) and [Strava integration](strava-integration.md) for full payloads, status codes, auth, jobs, retention, and deployment.

| Existing route | Onboarding use |
| --- | --- |
| `GET /api/auth/methods`; existing OTP/social auth routes | Discover configured sign-in options and authenticate. |
| `GET /v1/bootstrap`, `PUT /v1/devices/{deviceId}` | Establish athlete identity and the account's installation. |
| `GET /v1/catalog`, `GET /v1/config/training-policy` | Map canonical catalog IDs and pin the planning policy. |
| `GET /v1/integrations/strava` | Read `available`, actual connection/scopes, cached history, and recent jobs. |
| `POST /v1/integrations/strava/connect` | Body `{"autoPublish":false}`; receive authorization URL and one-time state. |
| `GET /integrations/strava/callback` | Provider-to-server callback; server exchanges the code and returns to the configured app link. |
| `POST /v1/integrations/strava/complete` | Only for a native flow that actually receives code/state; never also call it after the server callback consumed state. |
| `POST /v1/integrations/strava/history` | Request/reuse a history refresh; returns `202 {jobId}`. |
| `DELETE /v1/integrations/strava` | Disconnect, clear preview, cancel work, and queue revocation. |
| `POST /v1/sync/push`; pull/ack routes | Canonical aggregates, immutable baselines/contexts, plans and explicit activation. |
| `POST /v1/billing/apple/transactions`, `GET /v1/billing/entitlements` | Verify actual purchase/restore and determine access. |

OAuth uses `read`, `profile:read_all`, and `activity:read_all` for the existing read-only flow. Profile access is needed for detailed profile/zones; activity access controls history, including private activities. Honor granted scopes, not merely requested scopes. Keep `activity:write` out of onboarding unless the athlete separately opts into publishing. [Strava OAuth documentation](https://developers.strava.com/docs/authentication/).

Tokens, refresh, job execution, and rate limiting stay on the server. Open the returned authorization URL with the system authentication flow; after the app-link return, fetch authenticated status. Neither the app-link `status=connected` nor a local `wantsStrava` flag proves a usable connection. Handle cancel, missing scope, expired state, reauthentication, and an already-linked Strava identity without losing the draft.

## Backend work required

### 1. Add profile import and independently usable preview sections

Extend `server/src/strava/provider.ts`, the worker, persistence, and OpenAPI:

- Add a validated `/api/v3/athlete` reader for only the profile fields needed above. Treat null, absent, invalid, and unsupported fields explicitly; a missing weight must not fail a valid name import. Do not fabricate a measurement date from the profile's generic update time.
- Decouple profile/zones fetch from activity authorization. Today connection queues the history job only when activity scope is granted, and the worker starts with zones. A profile-only grant must still deliver available profile/zones even when history cannot run.
- Keep the existing `history` DTO compatible. Add a nullable `onboardingPreview` to connection status, containing independently stateful `profile`, `heartRateZones`, and `runningHistory` sections. Reuse existing history metrics rather than maintain another calculation. This is a **proposed response addition**, not a currently available field.
- Give the preview an opaque ID/revision bound to the athlete and connection generation, plus `generatedAt` and `expiresAt`. Each section needs `pending | ready | unavailable | failed`, a stable reason code, provenance, and coverage where applicable. Keep connection status distinct from import status. Expose `retryAfterSeconds` when deferred; avoid a fabricated percentage.
- Retain a review snapshot through its validity window, or detect a stale revision on acceptance and return a recoverable conflict. Never silently accept a different snapshot after optional best-effort fetching changes the preview.
- Apply the current seven-day preview expiration and disconnect/account-deletion cleanup to the new profile and review data too. Return only the signed-in athlete's preview. Do not put tokens in preview DTOs, logs, redirects, analytics, or sync.

Suggested reasons include `scope_missing`, `not_provided`, `not_supported`, `history_partial`, `no_activities`, `rate_limited`, `provider_unavailable`, and `preview_expired`. Use stable enums/codes in OpenAPI; iOS supplies localized text in English, Spanish, Brazilian Portuguese, and French.

### 2. Add typed storage for the full reviewed profile

The existing `AthleteProfileInput` stores timezone/locale/units/week settings/cloud-AI consent. It does **not** store the rich athlete profile. Add a versioned, sync-visible athlete-details aggregate and extend preferences/planning context deliberately. Every accepted field must survive pull/restore on another installation.

| Current iOS input | Canonical mapping / required extension |
| --- | --- |
| `name` | Athlete preferred name, 1–40 trimmed characters. Specify its relationship to auth display name; do not change auth identity/email through profile import. |
| `units` | Existing `athlete.distanceUnit` (`km`/`mi`) and `loadUnit` (`kg`/`lb`); add height display preference. |
| `age`, optional DOB import | Store an explicitly entered age with an as-of date, or an actual supplied DOB. Never invent January 1 or another birth date from an age. |
| `weight`, `height` | Nullable canonical kg/cm and provenance. Keep display preferences separate. |
| `runningLevel`, `strengthLevel` | Separate enums, including `new`, `beginner`, `intermediate`, `advanced`. Existing single `experienceLevel` lacks `new` and cannot represent both. |
| `runningGoal`, `strengthGoal`, optional race date | Existing `athlete_goal` records with agreed stable `goalType` codes. Race date is a calendar date, not midnight UTC. |
| `priority` | Map to `balanced`, `run_first`, or `strength_first`; define policy-owned numeric weights summing to one. Never derive wire values from translated labels. |
| `weeklyMeters`, `currentLiftDays` | Reviewed baseline metrics: recent weekly meters and current lifting sessions/week. Preserve zero as a valid answer. |
| `availableDays`, `strengthDays`, `sessionMinutes` | Existing availability rules plus explicit desired lifting sessions/week in preferences/context. Current frequency and desired frequency are distinct. Do not infer permission for two-a-days from one selected weekday. |
| `equipment`, `equipmentConfirmed` | Map to catalog equipment UUIDs; preserve confirmed bodyweight-only setup versus unanswered setup. Do not send Swift raw values as UUIDs. |
| `focusMuscles` | Add a typed canonical set with reviewed catalog mapping. Empty means balanced focus, not missing equipment or exercise exclusions. |
| `readiness`, `context` | Preserve `ready`, `returning`, or `adjusting` plus optional note (current UI limit 300 characters). This is context, not a medical diagnosis or cloud-AI consent. |
| Imported/entered HR zones | New structured profile data with source/custom indicator and reviewed boundaries; optional when unavailable. |
| Accepted running/strength records | Typed records with discipline, distance or exercise ID, performance, date, source and verification/coverage. Observed Strava efforts are not relabeled as verified all-time PRs. |
| `wantsHealth`, `wantsStrava` | Intent only. Actual connection, import consent, Health permission, and cloud-AI consent remain separate. |
| `membership` | Selected offer only; never an entitlement or proof of payment. |

Use explicit DTO mapping rather than serializing `OnboardingDraft`, which contains UI strings and conversion caches. `Features` accepts only bounded scalar values, not nested body profiles, zone arrays, PR collections, or a whole draft. Define and version its baseline metric keys; keep structured provenance in the new typed aggregate.

Mapping details to settle in the contract:

- Current `RunningGoal` includes general fitness, 5K, 10K, half marathon, marathon. `StrengthGoal` maps build → `strength`, muscle → `hypertrophy`, maintain → `maintenance`.
- Native weekdays use Foundation numbering (Sunday = 1). The current backend schema only constrains 1…7 without documenting the meaning. Specify the convention in OpenAPI and test all seven days before integration; do not silently assume ISO numbering.
- The onboarding baseline permits 0–250,000 m/week; local prescription generation currently has a narrower range. Preserve high-volume/zero baselines and return an actionable unsupported-planning state when necessary, rather than silently clamping the athlete's answer.
- Current optional body input bounds are 20–400 kg, 80–250 cm and integer age 1–120. Validate canonical quantities consistently on both sides; unsupported imported values remain reviewable instead of being silently rounded or clamped.
- Keep numeric wire data independent of locale; meters and integer seconds for training metrics, canonical kg/cm for body values. Display miles/lb/feet-inches with conversions. IDs and revisions use existing UUID/decimal-string conventions.
- Add mappings for all offered equipment/focus options. Catalog coverage must be checked before plan creation; don't quietly drop selections the server cannot represent.

### 3. Persist drafts and finalize setup reliably

The setup and read-only import routes must be usable by an authenticated athlete before buying membership. Billing access must not prevent reaching or completing the paywall journey.

**Proposed new authenticated endpoints, to implement and add to OpenAPI:**

| Route | Contract |
| --- | --- |
| `GET /v1/onboarding` | Return `schemaVersion`, `status` (`not_started`, `draft`, `completed`), nullable `draft`/`draftRevision`, semantic current step, and nullable completion receipt. Include enough state to resume on another phone; account identity comes from bearer auth. |
| `PUT /v1/onboarding/draft` | Save a full typed draft with nullable incomplete answers, `baseRevision` (`null` on first create), semantic step, canonical numeric values, and per-field import decisions. Return the new decimal-string revision. Require a UUID `Idempotency-Key`; reject revision conflicts instead of overwriting another device's draft. |
| `POST /v1/onboarding/complete` | Finalize an exact reviewed draft revision using a UUID `Idempotency-Key`, registered `deviceId`, catalog version, and policy ID. Verify Strava preview ownership/revision where used and validate reviewed Health/manual values, then transactionally persist the canonical setup, confirmed baseline, planning context, completion receipt, and normal sync changes. Return saved entity IDs/revisions and a sync-sequence hint. |

Draft schema must contain the fields in the mapping table, explicit nulls for optional/unanswered values, and no auth/provider secrets. Each imported-field decision records its source, field key, source-specific reference, and `accept | edit | reject`; edited values carry `editedFromSource` provenance. Strava decisions include the server `previewId` and revision. Health decisions include the local import batch/reference and measurement/coverage metadata described above; manual values need no provider reference. Do not trust a client-supplied `source:"strava"` as proof of origin: resolve accepted values against the owned server preview. Validate the bounded manual override independently.

For completion:

- It means **setup saved**, not purchase completed or plan activated. The completion receipt should contain `submissionId`, `completedAt`, athlete-details/baseline/context references, policy/catalog versions, and saved revisions. `GET /v1/onboarding` must recover it after a lost response.
- Bind idempotency to account, route and payload hash. Identical retries return the same outcome; the same key with different content is rejected. Recheck stored outcomes before rejecting a successful replay whose preview has since expired.
- Commit all required canonical setup records and the receipt in one transaction, with existing ownership/revision validation and sync feed entries. Failed validation must leave no partially completed setup. Do not make provider network calls while holding this transaction.
- The current `/v1/sync/push` commits each mutation independently; a 200 response can include rejected/conflicting entries. Do not describe a plain batch as atomic onboarding. Implement completion using the same domain validation/repository layer within one outer transaction; do not implement it as an HTTP loop over sync mutations.
- Use proposed error codes such as `ONBOARDING_REVISION_CONFLICT`, `IMPORT_PREVIEW_EXPIRED`, `IMPORT_REVIEW_REQUIRED`, `UNSUPPORTED_CATALOG_MAPPING`, and `ONBOARDING_VALIDATION_FAILED`; include field paths and a request ID. Distinguish recoverable conflicts, validation failures, auth expiry, and retryable service failures.
- Do not overwrite an already completed athlete on repeat signup. Resume the receipt; subsequent changes use normal explicit profile/replan flows. Never silently activate or replace an existing plan.
- Account bootstrap should expose onboarding status/receipt identity, or route immediately through `GET /v1/onboarding`. Local preview-completion flags are not authoritative. Preserve the existing offline training experience when a completed athlete temporarily cannot reach the server.

These endpoints are an onboarding coordinator over canonical training data, not a second profile/plan database. Continue using normal pull/ack to hydrate the saved aggregates; a response's latest sequence is not a safe replacement for the client's pull cursor.

## Import calculation and merge rules

Use `server/src/strava/history.ts` as the current metric implementation. The current import covers a rolling 365-day UTC interval, caps paging at 2,000 summaries, excludes flagged/out-of-period activities, deduplicates IDs, and treats Run/TrailRun/VirtualRun as running. Its rolling 28-day weekly average is `distanceM × 7 / 28` (rounded in the existing preview). **280,000 m over 28 days suggests 70,000 m/week**, before display conversion. Zero-activity days count; dividing only by active weeks would overstate the baseline.

Require coverage before automatic suggestions. `historyComplete:false`, partial scopes, and no returned activities are different states. Empty complete history means no recorded runs in that interval, not proof the athlete never ran. Ask whether the observed volume is representative; an athlete may have unrecorded training, a break, or multiple sources. Do not substitute yearly volume for current volume or infer race fitness from average training pace.

Keep the 28-day baseline's actual window and the broader import window distinguishable. `baseline_snapshot` uses date-only period fields; retain exact observation instants/timezone and coverage in the agreed metadata. The yearly `strengthSessions` value must not fill `currentLiftDays` without a new recent-window calculation and athlete confirmation. For either source, keep the exact recent sessions/week estimate (for example 10 sessions / 4 weeks = 2.5); the prototype accepts only integer current frequency, so ask for a representative routine rather than silently rounding the imported estimate.

Merge precedence: a reviewed manual choice wins; otherwise present source candidates with available measurement dates. A recent dated Health weight can be proposed ahead of an undated Strava weight, but the athlete chooses conflicts. Mark edited imports as edited, preserve their origin, and never auto-accept a later refresh. Missing values stay null. Do not add overlapping Strava, Health, and hybrd volume totals together. For the first release, select one reviewed history source per metric/window while still filling body/zone fields from either source. If combined history is added, deduplicate shared source/external IDs first; time/type/distance similarity is only a candidate match. Never merge ambiguous runs automatically or count a mirrored workout twice. Report distinct source coverage and ask for review when identity cannot be resolved.

Native `PersonalHeartRateZones` represents four increasing starts (Z2…Z5), currently constrained to 30…250 bpm. The backend preview exposes ranges and nullable upper bounds. Add an explicit conversion with boundary tests for a supported five-zone layout; preserve open-ended maxima and custom/default provenance. For Health's fractional boundaries, extend the canonical/native model with an explicit version and display rule instead of discarding precision to fit four integers. If ranges are malformed, noncontiguous, or otherwise incompatible, keep them as an unaccepted suggestion and request review. Do not invent max/resting/threshold HR from age, workout peak HR, or a zone boundary.

## Ownership, consent, and retention

Keep existing Strava integration controls: server-only encrypted tokens, bounded jobs/rate limits, preview expiration, webhook invalidation, deauthorization handling, disconnect and account deletion. New drafts must reference only their owner's connection generation; reconnecting another identity invalidates unaccepted suggestions from the old one.

Read permission, accepting an imported value, opting into outbound publishing, allowing Health reads, cloud-AI consent, and buying a membership are separate decisions. Do not automatically forward raw imported history/profile values to AI providers. Preserve source metadata on accepted data and follow the existing retention policy; expired provider previews must not remain indefinitely in abandoned draft copies. The existing policy for reviewed canonical baselines is documented in [Strava retention](strava-integration.md#retention-and-operations).

Logout/account switching must isolate saved drafts, caches, requests, and outbox state. Do not attach an anonymous draft to a different account without review. Restarting the onboarding preview must not revoke an actual connection or erase a real training account. Account deletion must cover the new drafts, details, receipts, and associated source metadata as well as existing data.

## Delivery and local acceptance

Backend owns typed schema/migrations/OpenAPI, profile import, preview state/identity, the finalization transaction, auth/provider configuration, and automated provider fixtures. iOS owns early connection UI, session/callback handling, Health reads, localized import review, canonical adapters, durable draft/outbox recovery, the local planner, StoreKit and Watch propagation of accepted settings.

Suggested delivery order:

1. Agree/publish the complete draft and athlete-details contracts, enums, weekday convention, catalog mapping, provenance, and completion receipt. Preserve backward compatibility for existing clients.
2. Implement independent Strava profile/zones/history previews and the native Health onboarding adapter with mocked fixtures, followed by source-neutral draft/complete persistence and restore tests.
3. Wire the native flow: authenticate → connect either/both sources → prefill and review available profile/baseline data → answer remaining questions → save setup → restore it on a clean installation. Health-only, Strava-only, both and manual-only paths are required in this slice.
4. Integrate candidate generation/plan acceptance and real StoreKit verification separately. Keep the current preview available until each real integration is testable.

For local work, reuse root `make up` (API/PostgreSQL/worker) and `make check` (isolated test DB, injected providers). No extra Strava worker container is needed. Unit/integration tests need no live provider credentials; real OAuth needs an enabled hybrd sign-in method, configured Strava client credentials, registered backend callback, app return link, and reachable API origin. Use the public HTTPS development origin described in [Strava configuration](strava-integration.md#configuration-and-docker) when testing callbacks/webhooks on devices. Keep all secrets in ignored environment configuration. Readiness alone does not prove OAuth or imports work.

Acceptance cases before enabling connected onboarding:

| Case | Required result |
| --- | --- |
| Health-only, Strava-only, both, or neither | Each route can finish onboarding; valid imported answers are prefilled and do not require retyping; goals/preferences still get explicit answers. |
| Shared Health body data and workouts; empty/partial reads | Correct dated body values and bounded running/lifting summaries; no walking-distance inflation or asserted read-permission status. |
| Health zones on OS 27; older OS or unavailable configuration | Exact fractional/open-ended boundaries and source preserved on supported OS; Strava/manual fallback works without invoking unavailable APIs. |
| Conflicting source values; mirrored workouts | Per-field choices and dates visible; selected values survive refresh; a run present in both sources contributes only once. |
| Full Strava grant with known history | Correct name/weight suggestions, exact zone boundaries, and independently calculated 7/28/365-day totals; review required. |
| Profile-only / activity-only / canceled grant | Available sections still work; unavailable sections have explicit reasons; manual onboarding remains usable. |
| Weight absent/zero/invalid, no height/age | No fabricated body measurements, no failed whole import; manual/Health fields remain available. |
| 28-day 280 km fixture; empty/partial/high-volume history | 70 km/week suggestion; explicit coverage; zero differs from unknown; no silent clamp above planner limits. |
| Missing HR, open top zone, malformed/incompatible ranges | Correct null/boundary handling; unsupported data is not silently converted or estimated. |
| Slow import, 429, expired token, provider outage, app termination | Persist/resume jobs and answers; bounded retries; no false connection/completion or late overwrite. |
| Manual edits followed by late import; overlapping Health workouts | Manual choices survive; no double-counted distance; source/measurement dates retained. |
| Lost completion response, duplicate tap, two devices, partial failure | Exactly one committed setup/receipt; conflicts actionable; full rollback where promised; replay recovers result. |
| Cross-account preview/draft, expired snapshot, disconnect/reconnect | Rejected ownership/stale references; no leaked suggestions; pending data cleared appropriately. |
| Clean install after completion | Name, optional body data, both experience levels, zones/records, goals, equipment, focus, schedule and readiness all restore. |
| Four-second animation and canceled/pending purchase | No invented success/entitlement; saved setup survives; verified purchase and plan activation remain separate. |
| Units, dates, languages, all weekdays | km/mi, kg/lb, cm/ft-in round-trip correctly; calendar dates/timezones and weekday mappings survive; codes render in all four languages. |

Existing automated suites are a starting point, not proof of the new behavior: extend `server/tests/integration/strava.test.ts`, auth/sync tests and native onboarding checks. Live-provider acceptance must use a consented test athlete with known expected values; it is separate from mocked tests. This documentation change does not start services, connect an account, or implement the proposed endpoints.
