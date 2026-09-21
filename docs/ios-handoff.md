# iOS integration handoff

`ios/` belongs to the separate iOS implementation. No Swift files, Xcode project or generated Swift client were added here.

## Contract and connection

Generate the client from `contracts/openapi.yaml` (OpenAPI 3.1); `make openapi` regenerates it from Zod/Hono and CI rejects drift. Sync payloads have named schemas for every canonical entity, including nested run/strength prescriptions and results. The same contract is served at `/openapi.json`.

Development API: `http://localhost:3000`. Override the server URL in the client; see `development.md` for physical-device access.

Better Auth owns `/api/auth/*` separately from the domain OpenAPI. Native Apple ID-token exchange uses `POST /api/auth/sign-in/social` with `{"provider":"apple","idToken":{"token":"APPLE_IDENTITY_TOKEN","nonce":"ORIGINAL_NONCE"}}`. Coordinate the nonce with the configured Apple provider; do not skip signature/audience validation. Preserve Apple's one-time user name locally where appropriate. Supply real `APPLE_CLIENT_ID`, `APPLE_CLIENT_SECRET` and `APPLE_APP_BUNDLE_IDENTIFIER` server-side before exercising this flow.

Local development supports `POST /api/auth/sign-up/email` with `name`, `email`, `password`, and subsequent `POST /api/auth/sign-in/email`. Use the response token as `Authorization: Bearer TOKEN`, store it in Keychain, and call `POST /api/auth/sign-out` to revoke it. Development password auth is forbidden in production.

## Initial setup and restore

1. Sign in and `GET /v1/bootstrap?deviceId=UUID`. It returns the athlete ID, current revision, sync availability, policy reference, effective entitlements and configured capabilities. Capabilities do not bypass consent or entitlement checks.
2. `PUT /v1/devices/{deviceId}` with `appVersion`, `pushEnabled`, optional `osVersion`/`pushToken`, and `pushEnvironment` (`sandbox` or `production`). Installation UUIDs belong to one athlete. A registered, non-revoked device is required for every sync call.
3. Fetch `GET /v1/catalog` and `GET /v1/config/training-policy`. Cache by catalog version and policy ETag. Only execute policy schema versions supported by the app. Use the policy's `id` in planning context and plans. Respect `minimumAppVersion`; old policy IDs remain valid for history.
4. Restore with `GET /v1/sync/pull?deviceId=UUID&cursor=0&limit=50`. Continue until `hasMore=false`. **Do not start a new device at bootstrap.latestSequence**: that would skip existing records.
5. Commit the returned entities and `nextCursor` together locally, then `POST /v1/sync/ack` with `deviceId` and `cursor`. Keep cursors and revisions as decimal strings, not floating-point numbers.

## Push and conflicts

`POST /v1/sync/push` accepts `{deviceId, mutations:[...]}`. Each mutation has its own UUID `id`, `entityType`, `entityId`, `operation`, nullable `baseRevision`, and typed `payload`.

- Create with `baseRevision:null`. Full updates/deletes require the last known revision. Delete payload is `{}`. Profile updates use the athlete ID; training preferences also use that ID.
- Each mutation commits independently; a conflict does not roll back successful siblings. Process results individually. Identical mutation ID/content replays the stored outcome. Changed content with the same ID is rejected. A corrected/rebased mutation needs a new ID.
- Retain the outbox entry on transport failure. Remove it after `applied`; surface/rebase conflicts and replace with a new mutation after a pull. Rejected mutation results remain stable on retry.
- Pull pages hydrate the latest entity state. Apply upserts only if their revision is newer (or for immutable records, if missing). Apply tombstones in feed order. Persist the supplied cursor even when an event's entity state is already known.
- Arrays and scalar units are bounded by the schema. Raw sensor traces are unsupported. Training dates are `YYYY-MM-DD` plus an IANA zone; instants are RFC3339, distances integer meters, durations integer seconds, loads decimal kg.

Typical onboarding creates goals, preferences, availability, equipment preferences, a baseline and a planning context. Create the block/context before its plan. Preserve immutable snapshots; changed context gets a new ID.

## Plans and results

Sync `plan_version` as one aggregate with nested prescriptions. New versions use new physical IDs throughout, retain logical workout IDs for matching sessions, and reference an accepted `basePlanVersionId` (null for the first plan). Drafts are immutable too. Activation is a mutation with `operation:"activate_plan"` and payload:

```json
{
  "expectedActivePlanVersionId": null,
  "accepted": true,
  "reasonCode": "initial_acceptance",
  "explanation": "Athlete accepted the proposed plan",
  "proposalId": null
}
```

A competing activation returns `PLAN_HEAD_CONFLICT`. Pull/recompute/reconfirm; never force an old head. Accepted snapshots, exact before/after change records and completed prescriptions are preserved. Drafts never become active just by syncing.

Sync `workout_result` as the actual-result aggregate; a set edit replaces that aggregate under its revision. Attach both the exact `plannedWorkoutId` and `logicalWorkoutId`, or leave both null for unplanned work. Segment/set prescription references must belong to that exact workout. Log explicit actual substitutions without changing prescribed exercises. `skipped` run results use `run:null`; skipped strength results have no exercises.

HealthKit imports additionally sync `activity_source_record` with provider `healthkit`, a stable external ID and fingerprint. Duplicate external IDs/fingerprints cannot create a second source. Matching/correction stays explicit, and source deletion does not silently erase performed history.

## Cloud intelligence and purchases

Set profile `cloudAiConsent:true` only after consent. Intelligence also requires an active/grace `pro` entitlement by default and server policy/configuration. Unavailable integrations return explicit errors; use local deterministic behavior when remote services are unavailable.

All intelligence requests require a UUID `Idempotency-Key` header. Reuse it for a network retry. Decision choices/models/prompts are server-controlled. Low confidence returns `disposition:"abstain"`; the local engine owns the conservative fallback and exact progression amounts.

Create a `coach_thread` through sync, then `POST /v1/intelligence/chat` with its ID, message and compact context. Relevant workout IDs must belong to the current active plan. JSON is the default; SSE emits one validated `complete` event. Conversation/messages/proposals are also restored through sync. Proposals do not edit plans. Run local validation, show the diff, obtain acceptance, then materialize a coach-origin plan and activate it with the proposal ID. Review-only acceptance/rejection is an `action_proposal` update; `accepted` alone does not apply a plan.

For StoreKit purchases pass **the athlete UUID as `appAccountToken`**. Submit the signed transaction to `POST /v1/billing/apple/transactions` on purchase/restore, and read `/v1/billing/entitlements`. Entitlement state also syncs. Production and sandbox are configured separately. The backend rejects purchases with missing or mismatched account tokens. The native app remains responsible for finishing StoreKit transactions and exposing subscription management.

## Account lifecycle

`GET /v1/account/export` returns canonical user data. `DELETE /v1/account` permanently purges the live account/data and invalidates all sessions; it requires a session created within ten minutes. On `REAUTHENTICATION_REQUIRED`, sign in again before retrying. Remove the local store and tokens after successful deletion. Account deletion does not cancel a StoreKit subscription or automatically disconnect Apple's authorization on the device; include those native flows in the account UI.

Errors use `{error:{code,message,details?,requestId}}`; branch on codes. `X-Request-Id` correlates sanitized server logs. Better Auth uses its own error format.

HealthKit normalization, local feature computation, candidate generation, interference checks, training progression, local scheduling, SwiftData/outbox handling, local reminders, WidgetKit/WorkoutKit and UI remain iOS responsibilities.
