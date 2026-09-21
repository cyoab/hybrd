# Backend MVP implementation

The backend now implements the control-plane responsibilities in the two original requirements documents. The iOS training engine, HealthKit import/normalization, local analytics, offline UI and native integrations remain client work. The original documents are unchanged.

| Area | Implemented |
| --- | --- |
| Authentication | Better Auth bearer sessions, native Apple provider, development-only password sign-in, athlete provisioning |
| Athlete | Profile/consent, goals, priority weights, availability/overrides, immutable baseline and planning context, exercise/equipment preferences |
| Catalog | Versioned stable IDs for 28 exercises, equipment, aliases, movement patterns and primary/secondary muscles |
| Plans | Blocks, immutable plan aggregates, repeatable run blocks/steps, strength exercises/sets/substitutions, expected-head activation, accepted before/after audit |
| Results | Separate actual run summaries/segments and strength sets, exact prescription references, partial/modified/skipped sessions, HealthKit provenance and duplicate detection |
| Sync | Typed per-entity mutations/projections, durable idempotency, optimistic revisions, per-mutation transactions, paginated change feed, tombstones, monotonic acknowledgements |
| Intelligence | Four bounded Jev decisions, structured coach JSON/SSE completion, validated proposals, consent/entitlement gates, persisted quotas, provider timeouts, usage/cost metadata |
| Billing | Apple's signed-data verifier, app/environment/product/account checks, restore replay, server notifications, renewal/grace/expiry/refund/revocation |
| Notifications | APNs HTTP/2 and signing, opt-in device targeting, delivery idempotency, invalid-token cleanup, operator command |
| Account | JSON canonical-data export; fresh-session hard deletion of auth, sessions and all athlete-owned records |
| Operations | Docker/Compose, isolated PostgreSQL tests, production image, migrations, policy publication/catalog commands, payload retention command, metadata-only logs and rate limits |

## Deliberate contract decisions

- `plan_version` is a whole immutable prescription aggregate; `workout_result` is a whole mutable actual-result aggregate. A set edit replaces its parent result with an expected revision. This differs from the architecture's illustrative granular set mutation and avoids partial relational graphs during restore. Individual rows remain relational in PostgreSQL.
- A new plan has new physical workout/block/step/exercise/set IDs. Preserve each unchanged session's `logicalWorkoutId`. Accepted plans cannot be edited; materialize a new version and explicitly activate it. Any prescription with a non-deleted result (including skipped work) must be copied unchanged into subsequent versions of that block.
- Changes contain current aggregate state, not a frozen historical payload for each feed event. An older event can therefore carry a newer revision. Clients apply revisions monotonically. Immutable plan versions and plan-change records retain the actual history.
- A per-athlete transaction lock is acquired before sequence allocation for every feed writer. This prevents commit-order gaps that could cause clients to miss updates. Unrelated athletes can progress concurrently.
- AI responses are fully buffered and validated before persistence or delivery. `Accept: text/event-stream` returns a `complete` event; it does not expose partial model tokens. Neither Jev nor the coach executes plan mutations.
- Coach actions currently support moving a workout, choosing a declared exercise substitution, and requesting a block replan. The local engine still computes and validates the concrete revised plan. Activation requires `accepted: true`, the expected active head, and the proposal ID for coach-origin plans.
- Structured decisions are `next_week_running_load`, `strength_progression`, `interference_severity`, and `schedule_candidate` (feasible candidates only). Additional primitives need a versioned request schema and server-owned criteria.
- Effective subscription status is recomputed from verified subscription chains. Reads and sync expire elapsed grants. No subscription is granted from unverified client claims; a development-only operator command exists for local AI testing.

## Retention and limits

Account deletion is synchronous, permanent deletion from the live database, including provider metadata and purchase associations. It requires a session created within ten minutes. A delayed AI result or Apple notification cannot recreate a deleted account. Infrastructure backups follow the separately configured backup retention period; deletion does not cancel an App Store subscription. The app must expose Apple's subscription management UI and account disconnection flow.

Ordinary sync deletes are tombstones; historical data and idempotency ledgers are retained for offline restore/replay. Deleting a coach thread tombstones its messages/proposals. The operator retention command removes compact AI context after 30 days and cached response copies after 90 days, retaining canonical conversations/decisions and idempotency metadata. An expired cache key returns `IDEMPOTENCY_EXPIRED`, not another paid call. Push delivery metadata remains to prevent duplicate sends. No raw GPS/heart-rate streams or full model prompts are logged or stored in invocation telemetry.

Default limits: 1 MiB request body; 100 mutations per push; 100 events per pull; 240 authenticated API requests/minute/account; 100 decisions/day, 30 coach requests/day, 10 AI requests/minute and two in-flight calls/account. AI limits are PostgreSQL-backed and UTC-day based. General API and webhook limits are process-local. Provider calls time out after 25 seconds. Failed provider attempts consume quota, and uncertain attempts are never automatically reissued with the same key.

## Verification and external setup

Tests use real PostgreSQL and Better Auth for persistence/authentication and injected providers for lifecycle scenarios. Adapter tests check the real Apple verifier rejects invalid JWS, OpenRouter request formats/response validation and provider failures. No paid requests, real purchases, Apple login or real push delivery are performed by tests.

Before a public launch, configure real Apple identifiers/credentials/products, an OpenRouter model and key, and APNs credentials; run Apple sandbox purchase/renewal/restore/refund and native sign-in/device tests. Publish reviewed training-policy values, configure backups/monitoring and deploy the service. These are environment/product validation steps, not placeholder backend routes. There are no `501` domain operations.
