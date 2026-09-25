# iOS → backend integration handoff

**Implemented AI foundation:** use [the agent API guide](agent-api.md) for the new durable read-only chat/analysis run endpoints, replayable SSE, typed artifacts and user-managed memory. Plan generation/mutation remain disabled capability flags. Existing intelligence endpoints below remain supported.

**Proposed AI expansion:** see the [AI agent implementation plan](ai-agent-implementation-plan.md) and [iOS harness contract review](ai-ios-harness-review.md) for server-generated plans, direct authorized edits, detailed analysis, memory and replayable progress events. Those contracts are proposals awaiting joint implementation; the intelligence endpoints documented below remain the current API.

Reviewed against the implemented server and current native app on 24 September 2026. This is the working guide for replacing local-only screens with authenticated backend integration. The API is implemented and tested; real provider credentials and native adapters are still required. Swift changes remain with the iOS agent.

Use [contracts/openapi.yaml](../contracts/openapi.yaml) as the wire contract. Generate the Swift API client from it, keep transport/domain mapping separate from SwiftData models, and use the runtime `/openapi.json` to compare the backend you are testing. `make openapi` regenerates the checked-in contract; CI rejects drift. Detailed companion guides: [authentication](authentication.md), [sync/development](development.md), [Progress](progress-metrics-implementation.md), [Strava](strava-integration.md), and [deployment](deployment.md).

The [onboarding → backend handoff](onboarding-backend-handoff.md) describes the next connected sign-up journey, including early Apple Health/Strava imports, source-aware auto-fill, the rich-profile requirements, and onboarding endpoints. The backend additions are now implemented; follow [the onboarding API guide](onboarding-api.md) for draft/complete routes, independent import previews, full profile restore, and native mapping requirements. Call `GET /v1/onboarding` immediately after bootstrap and canonical restore.

## 1. Bring up the integration environment

Run `make up` from the repository root. Only API and PostgreSQL are long-running development services. The `migrate` helper installs dependencies, applies migrations and seeds catalog/policy, then exits. Mailpit has been removed. Email OTP uses **Resend for both development and production** and delivers real email.

Configure the ignored `.env`, then run `make up` again:

```dotenv
AUTH_EMAIL_TRANSPORT=resend
RESEND_API_KEY=YOUR_RESEND_KEY
AUTH_EMAIL_FROM=signin@YOUR_VERIFIED_DOMAIN
DEV_AUTH_ENABLED=false
```

The sender must belong to a domain verified in Resend. Do not put these secrets in Swift, committed configuration or chat. Until credentials are supplied, use `AUTH_EMAIL_TRANSPORT=disabled`; the API remains available and `/api/auth/methods` advertises `emailOtp:false`. Selecting `resend` without a key/valid sender fails startup rather than pretending email is available. There is no password-login shortcut in normal Compose development.

| Environment | API origin / requirement |
| --- | --- |
| iOS Simulator on this Mac | `http://localhost:3000` |
| Physical iPhone | A reachable Mac LAN origin with a debug-only ATS/local-network setup, or an HTTPS development origin. The phone's `localhost` is the phone. See [device networking](development.md#ios-simulator-and-physical-iphone). |
| TestFlight / production | A deployed HTTPS origin, exact trusted origins, real app/provider identifiers and secrets. This repo has not provisioned a hosted backend. |
| Automated tests | `make check` uses an isolated disposable PostgreSQL database and injected providers; it does not send real email or publish Strava activities. |

Keep the origin configurable per build/environment. Native clients never use Compose hostnames such as `api` or `postgres`. `/health/live` confirms a process is running; `/health/ready` confirms PostgreSQL connectivity. Neither proves external providers are configured or reachable. Do not expose the database for physical-device tests.

Provider availability depends on the environment's configured credentials. Enable at least one real sign-in option before authenticated device testing. At runtime use `/api/auth/methods`, bootstrap capabilities, entitlements and Strava status; do not hard-code provider availability in the app. Provider configuration is independent: email OTP can be tested before Google/Apple, Strava or cloud AI are enabled.

## 2. Auth and session security

`GET /api/auth/methods` is public and returns Google/Apple/email availability plus OTP length/expiry/cooldown metadata. Show configured options and a useful unavailable state when none are enabled. The same successful sign-in registers a new account or restores an existing one; there is no separate passwordless signup endpoint.

### Email OTP

Signup and returning sign-in share a branded email with the app colors, an embedded logo, a selectable six-digit code and a plain-text alternative. Run `bun run email:preview` to review it locally without sending; see [email design](email-design.md). No native endpoint or payload change is needed for the branded template.

```http
POST /api/auth/email-otp/send-verification-otp
Content-Type: application/json

{"email":"athlete@example.com","type":"sign-in"}
```

A 200 `{"success":true}` means the provider accepted delivery, not guaranteed inbox placement. On 503 show a delivery error. Present a six-digit code field with `.oneTimeCode` autofill; keep the value as a string, including leading zeroes.

```http
POST /api/auth/sign-in/email-otp
Content-Type: application/json

{"email":"athlete@example.com","otp":"012345","name":"Athlete"}
```

`name` is optional for initial registration. A successful response contains `token` and `user`. Codes expire after ten minutes, are single-use, and allow five incorrect attempts. Resend rotates the code; the newest code replaces the old one. There is a 60-second send cooldown and three sends/address/hour. Honor `Retry-After` on throttling/delivery failures, allow correcting the email, and never auto-resend in a loop. Invalid/expired/used codes return 400; exhausted attempts can return 403. Full contract: [authentication.md](authentication.md#email-code).

### Google / Apple

Obtain a native provider **ID token**, then POST `/api/auth/sign-in/social`:

```json
{
  "provider": "google",
  "idToken": {"token": "PROVIDER_ID_TOKEN", "nonce": "ORIGINAL_RANDOM_NONCE"}
}
```

Use `apple` for Apple. Generate a fresh cryptographic nonce of 16–256 characters per attempt. Supply it to Google's nonce-capable SDK flow. For Apple, put SHA256(original nonce) on the authorization request and send the original nonce to the backend. The backend verifies signature, issuer, audience, expiry/token age and nonce. Do not send an OAuth access token in place of an ID token. Google needs the configured web/server client ID and native client configuration; Apple needs matching Services ID/bundle ID and a configured server-held client-secret JWT. SDKs, entitlements, callback schemes and first-authorization Apple name handling are in [authentication.md](authentication.md#google-and-apple).

Successful native exchange returns `{redirect:false,token,user}`. Verified matching emails can link providers to the same account; an Apple relay email and a different Gmail address remain separate accounts. Do not merge by display name or assume all three buttons reach the same athlete. The auth `user.id` is distinct from the training `athlete.id` returned by bootstrap.

### Native session rules

- Store the opaque hybrd session token in Keychain, scoped to API environment/account. Send `Authorization: Bearer TOKEN` on `/v1/*`. It is not a JWT the client should decode, and it is not the Google/Apple ID token.
- `GET /api/auth/get-session` validates the session and returns session/user data or no active session. Handle null as signed out as well as HTTP 401. `POST /api/auth/sign-out` with the bearer token revokes it. These Better Auth lifecycle routes are not currently in generated OpenAPI; add a small typed adapter alongside the generated client.
- The pinned Better Auth defaults are seven-day session expiry with renewal after a day of use. Preserve a returned `set-auth-token` header when present. There is no separate native refresh-token endpoint. On 401, pause authenticated requests/outbox draining and reauthenticate once; avoid parallel login prompts.
- On logout/account switching, stop old account requests and background tasks, revoke the device's push registration while authorized if applicable, sign out, clear credentials, and switch to an isolated local account store. Keep or discard unsynced work explicitly; never replay one account's outbox under another session. Do not claim server logout succeeded if offline.
- Use TLS outside explicit local debugging. Scope ATS exceptions to debug builds. Keep Resend, Strava, OpenRouter, Apple server and APNs secrets on the server. Never log tokens, OTPs, OAuth codes, webhook secrets, health payloads or full coach context; log sanitized error codes and `X-Request-Id` instead.
- Native bearer requests do not need a fabricated `Origin`. If an Origin is sent, it must be trusted. Browser OAuth retains server state/PKCE and origin protections. CORS is not authentication; all domain ownership comes from the verified session.
- The phone should handle backend auth/sync for the paired Watch in the first integration. Continue durable WatchConnectivity transfer; do not copy backend/provider secrets to Watch or treat a Watch receipt as a cloud acknowledgment.

## 3. First authenticated session and restore

1. Load the configured environment and sign in. Keep the returned auth user separate from training identity.
2. `GET /v1/bootstrap?deviceId=INSTALLATION_UUID`: read athlete ID/revision, profile preferences, registered-device flag, provider/policy capabilities, entitlements and sync metadata. Capabilities alone do not grant consent or entitlement.
3. Register a stable installation UUID with `PUT /v1/devices/{deviceId}` and `{appVersion,osVersion?,pushEnabled:false,pushEnvironment:"sandbox"}`. Reuse it for this account/install; register a distinct UUID after an account change because IDs are ownership-bound. Registration is retry-safe. Add a real APNs token only after permission/configuration; never fake one.
4. Fetch `/v1/catalog` and `/v1/config/training-policy`. Save their versions/checksums. Use returned catalog UUIDs and the policy's **id** in new training records. Honor supported policy schemas and `minimumAppVersion` on the client; the server does not negotiate an app upgrade from `appVersion`.
5. Restore with `/v1/sync/pull?deviceId=...&cursor=0&limit=50` on a new local replica. **Never start from bootstrap.latestSequence or push.serverSequence**: that skips unseen records. Continue until `hasMore:false`.
6. Commit each page's entities/tombstones and `nextCursor` together locally. Only then POST `/v1/sync/ack` with `{deviceId,cursor}`. Keep the persisted cursor across restarts.
7. Bind the existing screens to the restored account. Do not upload bundled sample plans or sample logs as the user's real history. Offer a deliberate local-data migration after identity/catalog mapping.

All sync calls require a registered, non-revoked device. On `DEVICE_UNAVAILABLE`, re-register the correct account/install before retrying. On `CURSOR_AHEAD`, rebuild the server replica from zero while preserving a separately stored, reviewed local outbox.

## 4. Endpoint map

All `/v1` routes require the hybrd bearer session. JSON requests use `Content-Type: application/json`. OpenAPI defines exact DTOs, nullable fields, bounds and response codes; the table gives integration purpose.

| Method and path | Native use |
| --- | --- |
| `GET /health/live`, `GET /health/ready`, `GET /openapi.json` | Public diagnostics/contract; not login checks. |
| `GET /api/auth/methods` | Available sign-in options. |
| `POST /api/auth/email-otp/send-verification-otp` | Request a sign-in code. |
| `POST /api/auth/sign-in/email-otp` | Verify a code, register/sign in. |
| `POST /api/auth/sign-in/social` | Native Google/Apple token exchange. |
| `GET /api/auth/get-session`, `POST /api/auth/sign-out` | Better Auth session lifecycle; separate adapter as above. |
| `GET /v1/bootstrap` | Athlete identity, device state, capabilities, policy summary, entitlements. |
| `PUT /v1/devices/{deviceId}`, `DELETE /v1/devices/{deviceId}` | Register/update or revoke an installation and push preferences. |
| `GET /v1/catalog` | Canonical exercises/equipment/muscle groups/aliases and catalog version. |
| `GET /v1/config/training-policy` | Published versioned policy; `If-None-Match`/ETag and 304 supported. |
| `POST /v1/sync/push` | Write typed training aggregates and supported reviews. |
| `GET /v1/sync/pull`, `POST /v1/sync/ack` | Read durable change pages and acknowledge local commits. |
| `GET /v1/progress/summary` | Dashboard snapshot; `periodDays=7|28|84`, named IANA `timezone`, private ETag. |
| `GET /v1/progress/comparisons/{comparisonKey}` | Page a comparison selected from summary; opaque cursor. |
| `GET /v1/progress/activity` | `from`, `to`, `timezone`, optional cursor/limit; max 366 inclusive dates. |
| `POST /v1/intelligence/decision` | A bounded advisory decision; UUID `Idempotency-Key` required. |
| `POST /v1/intelligence/chat` | Coach answer/proposals; same key requirement; JSON or finite SSE. |
| `GET /v1/billing/entitlements` | Current canonical access; an empty array grants no entitlement. |
| `POST /v1/billing/apple/transactions` | Verify a StoreKit signed transaction from purchase/restore. |
| `GET /v1/integrations/strava` | Availability, connection, preview and recent job states. |
| `POST /v1/integrations/strava/connect` | Begin consent; `{autoPublish}` returns authorization URL/state. |
| `POST /v1/integrations/strava/complete` | Optional native code handoff; usual server callback already completes it. |
| `POST /v1/integrations/strava/history` | Queue/coalesce a history refresh; 202 with job ID. |
| `PATCH /v1/integrations/strava` | Change `autoPublish`. |
| `DELETE /v1/integrations/strava` | Stop sync/purge preview and queue revocation; 202. |
| `POST /v1/integrations/strava/jobs/{jobId}/retry` | Retry only a safely retryable job. |
| `POST /v1/integrations/strava/jobs/{jobId}/reconcile` | Verify an existing remote activity for an uncertain publish. |
| `GET /v1/account/export`, `DELETE /v1/account` | Export canonical data / fresh-session permanent deletion. |

There are no separate REST CRUD routes such as `/v1/workouts`, `/v1/plans` or `/v1/profile`; those writes go through sync. Provider-only `/webhooks/apple`, `/webhooks/strava/{secret}` and `/integrations/strava/callback` are configured by the backend operator. The phone never sends provider webhook events.

## 5. Versioning and wire conventions

| Version/identifier | Client rule |
| --- | --- |
| `/v1` | Domain API major version. `/api/auth` uses the pinned Better Auth contract, independently. There is no custom version-negotiation header. |
| OpenAPI `info.version` / root service version | Currently `0.1.0`; build metadata, not a sync cursor or schema version. Pin the generated client to a known repo contract revision and review regeneration diffs. |
| `schemaVersion` | Explicit data shape version. Baseline, planning context and coach context currently require `1`; Progress exposes schema/rules `1`. Reject unsupported data safely before persisting/acting on it. |
| Training policy `id`, `version`, `checksum`, `minimumAppVersion` | Immutable policy identity, revision and client-compatibility guidance. Cache/revalidate with ETag; preserve the policy referenced by historical plans. |
| Catalog `version` | Cache identity/mapping version. Refresh mappings when it changes; do not silently rewrite existing prescriptions. |
| Plan `id` vs `logicalWorkoutId` | A new immutable plan uses new physical prescription IDs; unchanged logical sessions retain logical IDs. Results reference the exact historical prescription they performed. |
| Entity `revision`, sync `sequence`/cursor | Decimal strings, not floating-point values. Compare numerically with a lossless representation, not lexicographically. Gaps in sequence are valid. |
| Progress cursor | Opaque, signed, query/account/revision-bound and expiring. Do not parse it or use it as a sync cursor. |
| Strava IDs | Decimal strings to avoid precision loss; distinct from canonical UUIDs. |

Dates are `YYYY-MM-DD`; performed instants are RFC3339 with an offset; zones are IANA identifiers. Wire distances are integer meters, durations integer seconds and loads decimal kg, regardless of display units. Parse fractional seconds and nullable instants. Preserve a stored training date/timezone through travel and later edits rather than deriving it again from the phone's current timezone.

Inputs are strict: do not serialize entire local models, attach unrecognized keys, or replace null with zero. Compact `Features` maps permit at most 64 keys with scalar number/bool/string/null values (strings max 200 chars); they are not arbitrary nested JSON storage. Request bodies are limited to 1 MiB; sync batches and pull pages are at most 100 entries. Reference the generated schema for aggregate-specific limits.

For future compatible response additions, ignore unknown optional fields where the generated decoder permits it. For unknown required schema versions, entity types or enum values, keep an actionable upgrade/unsupported-data state and do not advance a sync cursor past data that was not safely persisted. A breaking server contract requires coordinated versioning; SQL migration numbers are internal and never sent by the native app.

## 6. Durable sync and conflicts

Persist a local outbox entry atomically with each user edit. A mutation contains a stable `id`, `entityType`, `entityId`, `operation`, nullable `baseRevision` and its full typed `payload`. Retain the exact mutation ID/content for transport retries, including after app termination. Serialize local edits to the same entity so a second edit rebases on the revision actually accepted by the server.

```json
{
  "deviceId": "11111111-1111-4111-8111-111111111111",
  "mutations": [{
    "id": "22222222-2222-4222-8222-222222222222",
    "entityType": "coach_thread",
    "entityId": "33333333-3333-4333-8333-333333333333",
    "operation": "create",
    "baseRevision": null,
    "payload": {"title": "Training coach"}
  }]
}
```

The UUIDs are illustrative; generate real stable IDs. On create use `baseRevision:null`. On update/delete supply the current revision. Updates are full aggregate replacements, not patches; delete payload is `{}`. Profile uses `entityType:"athlete"` and the bootstrap athlete ID; training preferences use that same ID.

`POST /v1/sync/push` normally returns HTTP 200 with one result per mutation: `applied`, `conflict` or `rejected`. Inspect every result. Each mutation commits independently; a later failure does not undo earlier entries. A lost connection can leave a partial batch committed. Retry identical IDs/content to recover outcomes. The replay ledger also retains conflicts/rejections: a corrected/rebased attempt needs a **new mutation UUID**. Do not blindly retry a conflict under the old key or resend a different body with that key.

After successful pushes, pull to catch authoritative state and concurrent device changes. Feed pages hydrate each entity's current aggregate, which can be newer than the event itself. Apply only newer entity revisions, preserve immutable snapshots, and process tombstones/feed order. Keep unsent local edits separate from the server replica; don't overwrite them invisibly with a pull. Commit entities and cursor together, then acknowledge. `serverSequence` is a hint, not an acknowledgment of what this device has read.

Supported writes: athlete, goal, preferences, availability rule/override, baseline, planning context, equipment/exercise preferences, block, plan version, workout result, HealthKit source record, coach thread and proposal review. Coach messages, structured decisions, entitlements and plan-change audits arrive through pull after server operations; do not manufacture writes for them.

Trigger sync after login, foregrounding, network recovery, explicit refresh and accepted edits/workout saves. Coalesce concurrent triggers, back off transient failures with jitter, and stop on auth or contract errors. There is no persistent sync socket. Background execution and APNs are opportunities to pull, not delivery guarantees.

### Plans, results and immutable history

Create goals/preferences/availability/equipment and a confirmed baseline, then a planning context referencing the published policy. Create the training block/context before its plan. `plan_version` is a complete nested run/strength prescription aggregate. Draft and accepted plans are immutable. A revision/replan creates new physical IDs while preserving logical workout identity as appropriate. A prescription with a non-deleted result (including skipped work) must be copied unchanged into subsequent versions of that block.

Activate through sync with `operation:"activate_plan"`, the plan ID/current revision and:

```json
{
  "expectedActivePlanVersionId": null,
  "accepted": true,
  "reasonCode": "user_acceptance",
  "explanation": "Athlete accepted the initial plan",
  "proposalId": null
}
```

Use the previous active plan ID on later activations. `PLAN_HEAD_CONFLICT` requires pull, recomputation and renewed acceptance. A coach proposal can only apply through the same validated new-plan/activation flow; marking it accepted alone does not mutate a plan.

`workout_result` is a separate mutable actual aggregate, including run summaries/segments or strength sets. Link both exact `plannedWorkoutId` and `logicalWorkoutId`, or leave both null for unplanned work. Nested prescription references must belong to that exact workout. Replacing a set replaces the parent aggregate under its revision. Preserve actual substitutions and extra sets; never rewrite prescriptions to match actuals. Skipped runs use `run:null`, skipped strength uses no exercises. HealthKit source records preserve stable external IDs/fingerprints and explicit matching; deleting a source link does not erase performed history.

## 7. Native migration work before uploading existing data

Current `ios/README.md`, `PROFILE-INTEGRATIONS.md` and `WORKOUT-RECORDING.md` describe the existing local screens/models. Their statement that the Strava backend is deferred is now superseded by this handoff and [strava-integration.md](strava-integration.md). Native wiring and credentials remain outstanding.

| Existing local data/behavior | Required integration work |
| --- | --- |
| SwiftData `TrainingStore`, local Codable models and sample plan | Add explicit DTO adapters and a versioned migration. Separate demo records, immutable prescription snapshots, mutable actuals, server revisions, dirty local edits and the durable outbox. Keep current offline behavior. |
| Bundled 876-exercise catalog with string IDs | Map reviewed entries to UUIDs returned by the backend catalog (currently 28 seeded exercises) with a versioned mapping. Do not cast/hash arbitrary local names into invented server IDs. Unmapped movements need catalog work or remain local with an explicit state. |
| Rich athlete profile: DOB/height/weight, separate experience, HR zones, PR collections | `AthleteProfileInput` only stores timezone/locale/units/week boundary/cloud-AI consent. Preferences and compact reviewed baseline features cover some training context. There are no dedicated structured cloud fields for all rich-profile values/PR provenance; preserve them locally until an agreed mapping or additive backend contract exists. Do not hide arbitrary arrays in `Features`. |
| Native active workout time excludes pauses | Canonical `durationS`/`run.durationS` are used as elapsed duration by export/comparison code and must agree when both are present. Use measured elapsed end-minus-start for this integration, retain active time locally, and never claim active time is independently measured moving time. A separate cloud active-duration field would require a contract addition. |
| Recorded start/end, local timezone and legacy logs | Map real performed dates/instants where known. Legacy records without performed timing use `dateBasis:"loggedDate"` and known logging date/zone/optional `loggedAt`; do not invent start/end or copy the plan date. Missing timing leaves Strava export pending details. |
| iPhone / Watch recording and repeated WatchConnectivity receipts | Reuse the stable recording/result UUID and exact historical plan references. Phone deduplicates receipts and queues cloud sync after its local commit. A native hybrd recording is `sourceType:"manual"` in the current backend contract, even when hybrd also saved it to Apple Health. A subsequent HealthKit import links to that existing actual. |
| Routes, raw HR samples, overlapping manual/automatic laps | Keep streams/routes on device and in authorized Health storage. The sync API accepts bounded summaries/segments, not raw `RunRecording` JSON. Don't double-count overlapping lap lists; native lap kinds not representable in the contract remain local pending a schema extension. |
| Strength logs and display units | Convert exactly once to canonical kg/meters; preserve actual RIR (including zero), nullable RPE, load convention, stable exercise IDs and exact set references. Send only actual completed work as completed. |
| Offline Progress screen | Migrate canonical dates/identities first, then choose one authoritative local or server snapshot per render. Do not add overlapping server, HealthKit and Strava totals. |

These are integration boundaries, not instructions to discard valid local measurements or silently truncate user profiles. The first live test can use newly created, canonically mapped records while the historical migration is implemented separately.

## 8. Coach, decisions and streaming

**No WebSocket endpoint is implemented or required for the current coach.** The backend accepts normal HTTP POST and optionally returns Server-Sent Events. Current SSE is a **single completed event after the entire provider response is validated and persisted**, not progressive text-token streaming. Show a waiting state; do not expect token deltas, heartbeat events, a reconnect cursor or an immediately flushed connection.

Create/sync a `coach_thread` first. Then:

```http
POST /v1/intelligence/chat
Authorization: Bearer TOKEN
Idempotency-Key: REQUEST_UUID
Content-Type: application/json
Accept: application/json

{
  "threadId": "33333333-3333-4333-8333-333333333333",
  "message": "Can we move my long run to Sunday?",
  "context": {
    "schemaVersion": 1,
    "activePlanVersionId": null,
    "summary": "A short athlete-reviewed training summary",
    "relevantLogicalWorkoutIds": [],
    "recentFeatures": {}
  }
}
```

For plan changes provide the actual active plan ID and relevant logical IDs from that plan. The server validates ownership and active-plan references and loads relevant prescriptions/history. Do not send raw Health/GPS streams or the full local database. Message length is at most 4,000 characters, summary 4,000, relevant logical IDs 12, and context is bounded server-side.

Use `Accept: text/event-stream` for the alternative response:

```text
event: complete
data: {"type":"complete","messageId":"...","content":"...","actionProposals":[],"policyVersion":2}

```

A native SSE adapter can consume a POST byte stream (for example `URLSession.bytes(for:)`) and frame events at blank lines. Validate HTTP status and Content-Type before decoding; errors still use the JSON domain envelope even when SSE was requested. Treat EOF without a valid `complete` event as an uncertain outcome, not a completed answer. There is no GET EventSource route, `Last-Event-ID` replay or server cancellation endpoint. JSON is the simplest first client integration and delivers the same persisted result.

Provider requests have a 25-second timeout; the API's HTTP idle timeout is 60 seconds. Allow a bounded client request window that covers provider and database work (for example 60 seconds). Client cancellation/background suspension does not prove the server stopped or rolled back the request.

Persist the UUID `Idempotency-Key` and request body before sending. Retry the same body/key after an unknown transport outcome. Completed retries return the cached response without a second provider invocation. `AI_REQUEST_IN_PROGRESS` / `THREAD_BUSY` mean wait; `AI_REQUEST_INDETERMINATE` means don't silently issue a new billable attempt. Pull to reconcile canonical coach records. A definitively failed invocation needs a new key for an explicit new attempt; `IDEMPOTENCY_EXPIRED` means restore canonical records through sync. Permit one in-flight message per thread in the UI.

Cloud AI requires `cloudAiConsent:true` in the synced athlete profile, configured provider/model, a published enabled policy and an active/grace `pro` entitlement by default. Bootstrap capabilities report configuration/policy availability; entitlements and consent remain separate checks. Keep the labeled local coach available offline/unconfigured. For local testing an operator may run `docker compose exec api bun run ops grant-dev-entitlement ATHLETE_UUID pro`; this is forbidden in production and is never a client-accessible grant.

`POST /v1/intelligence/decision` uses the same idempotency discipline with typed, server-defined choices. Current decisions are `next_week_running_load`, `strength_progression`, `interference_severity`, and `schedule_candidate`; consult their generated union schemas. `disposition:"abstain"` requires the conservative local fallback. Responses are advisory. For proposed schedule/substitution/replan changes, display the diff, perform local constraints checks, obtain explicit acceptance, then materialize/activate a new plan with the proposal ID. Future progressive token streaming would need a new documented event/error/cancellation contract; it is not enabled by merely switching the client to SSE or WebSockets.

## 9. Strava

Use backend linking, not a second Strava SDK/API client with persisted provider tokens. `/v1/integrations/strava` is the availability source; Strava is not a hybrd sign-in option.

1. Let the athlete choose connection and automatic publishing. POST `/connect` with `{autoPublish:true|false}` and open the returned `authorizationUrl` using the system/native authorization flow.
2. Strava returns to the backend callback, which exchanges the code and returns to `STRAVA_APP_RETURN_URL` (default `hybrd://integrations/strava?status=connected`). Configure the native scheme/universal link. On return, fetch authenticated status; never trust a deep-link status alone. Do not call `/complete` again after the server consumed the state.
3. Poll status with backoff while history is pending; `POST /history` requests a fresh/coalesced import during onboarding or later plan creation. Stop frequent polling when the screen is hidden or no job is pending.
4. Review imported HR zones, 7/28/365-day volume/pace and observed best efforts before replacing manual entries. Check expiry/completeness/coverage. Open-ended HR maximum is null, not zero. Best efforts are sampled runs within the imported year, not guaranteed all-time PBs. Missing goals/equipment/availability/strength PBs remain user input.
5. Accepted metrics become a new baseline (`source:"strava"` or `mixed`) and planning context via sync. The import does not create canonical workout results or automatically modify a plan.
6. Normal committed native workout sync triggers outbound publication if enabled. Do not call Strava directly or enqueue a second export from the phone. Imported HealthKit-only results are excluded to prevent loops.

Handle `not_connected`, `connected`, `reauthentication_required`, `disconnecting`, and `disconnected` distinctly. `needs_details` jobs need real timing in the workout. `needs_review` means Strava may already have accepted a publish; do not force a repost. Safe retry and verified remote-ID reconciliation routes are documented in the [full Strava contract](strava-integration.md). Turning publishing off cancels unsent eligible jobs; an already sent request can finish. Disconnect stops new work and asynchronously revokes the grant.

Current Strava exports are Run/WeightTraining **summary activities** with start time, elapsed time and running distance. GPS routes, HR streams, laps and strength sets are not uploaded. Later local edits/deletions are not propagated to already published Strava activities. The backend handles scopes, encrypted credentials, refresh, rate limits, retries, webhook invalidation/deauthorization and revocation. Live testing needs configured app credentials plus public HTTPS callback/webhook registration.

## 10. Progress, purchases and notifications

Progress summary accepts 7/28/84 days (different from Strava's 365-day preview). Use the profile's named timezone, support private ETag revalidation and 304 with no body, and refresh after synced result corrections. Cache keys must include account/environment/query; don't reuse another athlete's cached response. History cursors are opaque and expire on edits; restart the same query on `409 PROGRESS_CURSOR_EXPIRED`. Activity history has inclusive dates and a bounded page size. See [Progress migration and contract](progress-metrics-implementation.md) for milestones, provenance and comparison grouping.

For StoreKit purchases set **the bootstrap athlete UUID as `appAccountToken`**. Submit `{signedTransaction:"SIGNED_JWS"}` to `/v1/billing/apple/transactions` on purchase/restore and consult `/v1/billing/entitlements`. The backend verifies signatures, environment, product and ownership; native purchase completion/transaction handling and subscription management remain on-device. StoreKit billing credentials are separate from Sign in with Apple credentials. A local StoreKit test file is not a substitute for testing Apple's server-verified sandbox flow.

APNs registration is opt-in through the device endpoint. `sync_hint` and `coach_ready` are supported delivery types, but current backend sends are operator-triggered; there is no automatic notification scheduler or public send endpoint. On a hint or foreground transition, pull canonical state; push payloads are not a data replica. Native rest timers/local reminders remain local and need no socket. Background delivery can be delayed/missing, so the next foreground pull must recover everything.

## 11. Errors, retries and account lifecycle

Domain errors use `{error:{code,message,details?,requestId}}`; auth errors use Better Auth's `{code,message}` shape. HTTP 200 sync responses still contain per-mutation failures. Handle empty 202/204 and 304 bodies without attempting JSON decoding. Log the response `X-Request-Id` for server diagnostics.

| Outcome | Expected client behavior |
| --- | --- |
| 400 / `VALIDATION_ERROR` | Fix the DTO/mapping; don't retry the same invalid payload automatically. |
| 401 / no active session | Pause sync, clear invalid credentials, sign in once, then resume only the matching account's work. |
| 403 `DEVICE_UNAVAILABLE` | Register/recover the correct installation. |
| 403 `AI_CONSENT_REQUIRED` / `ENTITLEMENT_REQUIRED` | Present the corresponding consent/access state; don't retry blindly. |
| 403 `REAUTHENTICATION_REQUIRED` | Fresh interactive sign-in before the sensitive operation. |
| Conflict / `PLAN_HEAD_CONFLICT` | Pull current state, review/rebase and create a new mutation/acceptance attempt. |
| 409 `IDEMPOTENCY_KEY_REUSED` | A key was reused with different content; correct the client outbox/request bookkeeping. |
| 413 | Reduce batch/aggregate size without breaking atomic aggregate semantics. |
| 429 | Honor `Retry-After` when present; otherwise use capped backoff/jitter. General API quota is 240 requests/athlete/minute per instance; AI and OTP limits are separate. |
| 502/503 | Distinguish unavailable configuration from transient provider failure. Retry only idempotent operations with their original keys after an unknown outcome. |
| Network loss / app suspension | Keep durable outbox/request state. Server completion may have occurred. Reconcile after connectivity returns. |

`GET /v1/account/export` returns canonical training/coaching records, excluding credentials, provider token envelopes and raw routes. It is not a backup of native-only fields. `DELETE /v1/account` requires a session created within ten minutes and permanently removes live account data/sessions. Require the user's destructive-action confirmation in the native UI and online completion; after success clear that account's local store, tokens, pending requests and cached Watch data. Strava grant revocation is queued with an encrypted envelope retained at most seven days. Account deletion does not cancel an Apple subscription or replace native Apple-authorization/account-management flows.

## 12. Suggested implementation and acceptance order

| Stage | Must work against the real backend |
| --- | --- |
| A — connection/auth | Configure one real provider; discover methods; request/read a Resend OTP; sign in; reject a replayed/wrong code; relaunch with Keychain session; logout; expired-session recovery. Then exercise Google/Apple nonce, first/returning login and account separation. |
| B — canonical setup | Bootstrap/register; fetch catalog/policy; map supported exercises and units; save real goals/preferences/baseline/context; restore from zero on a clean installation. Show unmapped/profile-only fields explicitly. |
| C — sync/plans | Persist outbox before send; lose network after a commit and replay without duplication; recover after app kill; resolve two-device revision conflicts; activate a plan using the expected head; preserve historical prescriptions. |
| D — workouts/Progress | Sync a new run and strength result; deduplicate repeated Watch/HealthKit receipts; retain real timing/timezone/RIR; edit and delete actuals; refresh Progress/ETags/cursors; restore from another device without double totals. |
| E — Strava | Authorize full/partial scopes; cancel/expire authorization; review history and coverage; publish one new run/strength summary; display pending/incomplete/uncertain states; verify webhook invalidation and disconnect. |
| F — coach/billing | Enable consent/test entitlement/provider; create a thread; consume JSON and one-event SSE; recover a lost response using the same key; review a proposal without automatic plan edits; test explicit activation and StoreKit sandbox restore/access loss. |
| G — account isolation | Switch users without sharing caches/outbox/push tokens; export; require fresh sign-in for deletion; verify deleted sessions and local/Watch data are removed; test app relaunch. |

Run `make check` for backend regressions. Native UI/network/real-provider acceptance remains a separate device test pass: mock success screens do not establish that credentials, delivery, callback domains, sandbox products or sensors work. During provider outages/unconfigured states the existing local training UI should remain usable with clear sync/availability status.
