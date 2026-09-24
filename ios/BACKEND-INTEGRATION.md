# Email and core backend integration

The iPhone app now connects to the checked-in backend contract. The official source remains `ios/` in this repository; the Bitrig workspace links to it. This is the first connected testing slice: email authentication, manual onboarding, athlete setup, plans, actual workouts and Progress. It is not a production release of every backend capability.

## Start a local test

From the repository root, with Docker Desktop running and the repository’s existing `.env` configured:

```sh
docker compose up --build --detach --wait
```

The API and its readiness endpoint are available at `http://localhost:3000` and `/health/ready`. The normal Compose API disables development authentication; the native client uses real email OTP and an opaque bearer session. For inbox delivery, `.env` needs `AUTH_EMAIL_TRANSPORT=resend`, `RESEND_API_KEY` and an authorized `AUTH_EMAIL_FROM`, as described in [authentication](../docs/authentication.md). If email is disabled, the app reports that capability and does not fake sign-in. Never copy these credentials into Swift, Project.json, test fixtures or commits.

Build/run using Bitrig. On the welcome screen, choose **Create account** or **Already have an account? Sign in**. From the existing local app, open **Athlete → Connect with email**. Open **Connection settings**, choose **Use local Docker backend**, then **Save and check connection**. Enter an email address and the six-digit code from the newest email. This either creates the account or restores it.

For an actual iPhone, localhost refers to that phone. Use a reachable HTTPS development endpoint and matching backend deployment configuration. The normal Compose port remains bound to Mac loopback; this change does not expose it on the network. DEBUG permits HTTP only for localhost/loopback; release builds require HTTPS. There is no production domain embedded in this change.

## Domain and version settings

| Setting | Local example | Behavior |
| --- | --- | --- |
| Server address | `http://localhost:3000` | Origin only, without a path, query or credentials |
| API version | `v1` | Domain requests use `/v1/…`; another supported version needs no URL edits |
| Authentication path | `/api/auth` | Email methods, OTP, get-session and sign-out have independent routing |

The connection check verifies readiness, the configured bootstrap path in `/openapi.json`, and advertised email availability. A version setting changes routing, not the compiled schema: an incompatible API still requires regeneration/mapping changes. The backend currently implements `v1`.

Sign out before changing environment settings. Credentials are Keychain-scoped to origin, version and auth path. Account data, request journals, device IDs and outboxes are separately scoped to the environment and bootstrap athlete UUID. Switching users/servers never uploads the demo dataset or another account’s queued work. Settings remain available from the email screen after sign-out.

## Connected behavior

- Email OTP preserves leading zeroes, uses the advertised expiry/cooldown contract, honors Retry-After and supports entering an already received code after relaunch. There are no automatic resend loops.
- Session restoration validates `/get-session`. Rotated bearer tokens replace the matching Keychain credential. A 401 clears credentials and requires sign-in. Cookie-free transport refuses redirects.
- Bootstrap registers an account-specific installation, fetches catalog and policy, validates supported policy/app versions, and restores canonical entities through pull/ack.
- Onboarding saves each confirmed step, preserves local unsubmitted edits, resumes server drafts, and completes using durable idempotency keys. Conflicts retain both pending and server answers for explicit review. Unsupported provider-derived drafts are not silently rewritten as manual data.
- Recap completion saves the athlete’s setup, baseline and planning context. The four-second transition is only a minimum presentation time; successful server completion is required to continue. It does not pretend a plan or membership was created.
- New accounts start with an empty plan. Save the athlete profile, then review and accept a deterministic starter block. It uses the backend catalog and policy IDs, creates an immutable plan, and activates it with the expected previous head. Profile edits must sync before generating a plan from that setup.
- Profile saves sync units, body details, personal HR zones, PRs, experience, goals, availability, equipment and baseline changes. Extra canonical fields not edited by the native UI are retained. Reported age is displayed without inventing a date of birth.
- Run/strength actuals use stable result IDs, historical prescription references and canonical meters/kg. RIR zero remains meaningful. Phone receipts deduplicate Watch results; unmatched Watch runs require review rather than being silently assigned to an account.
- Progress uses `/progress/summary` for 7/28/84-day totals, activity, milestones and matched comparisons, with account/query-scoped ETags and 304 handling. History and drill-down use the synced canonical results. A server summary replaces corresponding local totals; they are never added together.
- The Watch continues to record locally and transfer through WatchConnectivity. Its cloud uploads happen through the signed-in phone; the Watch has no independent bearer login in this slice.

## Offline and recovery behavior

`BackendReplica` atomically stores each pull page and its cursor before acknowledging. Decimal revisions/cursors stay strings. Push/bootstrap sequence hints never advance the pull cursor. Tombstones remain in the replica. Unknown schema/entity data fails rather than being skipped while advancing the cursor.

The outbox stores exact payloads and mutation UUIDs before upload. It sends dependent mutations sequentially and resumes after a lost response or restart. Conflicts/rejections remain visible in **Account & sync**; **Use server data** requires confirmation and discards the remaining pending local edits. Applied operations are not rolled back. An unresolved batch blocks a second mutation batch so stale revisions are not silently queued. Local workout draft checkpoints can continue to save.

The app attempts sync after edits, on foreground entry and through **Sync now**. It does not currently run a background network monitor or promise background delivery. If offline, pending edits remain account-scoped. Previously hydrated accounts can restore cached setup/data when the initial bootstrap transport is unavailable. Retry is explicit after other connection/setup failures.

Active/recovered runs retain access to recording controls. An expired session during a connected run allows reauthentication only into that same account; account switching waits until the run is resolved. Credentials can be cleared locally if the server is unreachable; local sign-out does not revoke a server session. Pending data stays on this device for the original account.

## Measurement and contract boundaries

Canonical `durationS` and `run.durationS` are elapsed end-minus-start, including pauses. Native active stopwatch time remains in the local recording and is not falsely labeled measured moving time. A manually entered run may send its entered duration, but logs without known performed timestamps use `loggedDate` and never invent starts/ends or copy planned dates. Individual strength-set completion timestamps are omitted unless actually measured.

Routes, detailed HR streams and overlapping automatic/manual laps remain local (and in authorized Health storage where the existing recorder writes them). The current backend cannot losslessly represent all native lap kinds/time bases. Average/max HR can be sent as bounded summary values. Sync hydration retains the original local recording alongside the canonical summary. A fresh device receives the summary, not raw routes.

The backend baseline allows 0–250 km/week. The existing starter generator supports 3–150 km/week; values outside that range remain saved, with starter generation unavailable rather than silently clamped. The server exercise catalog is smaller than the bundled public library: only exact catalog names/aliases are accepted. A gym setup without compatible starter exercises produces a clear error. No synthetic catalog UUIDs are generated.

## Intentionally outside this test slice

Google and Apple sign-in, Strava, Apple Health profile/history import, AI consent/requests, remote coach and StoreKit billing are not invoked by connected screens. Existing local workout sensor recording is unchanged. Connected setup bypasses the membership preview and grants no paid entitlement. The local onboarding/paywall demo remains accessible through **Preview onboarding without an account** and uses separate persistence.

Account export/deletion UI, push registration, provider consent/import/review UI, production purchase handling, historical demo-to-account migration, specialized result correction/deletion screens and independently authenticated Watch networking remain follow-up work. Existing canonical data is decoded/restored, but this does not claim a UI for every backend endpoint. No real-provider acceptance or production deployment was performed.

## Automated checks

```sh
bash ios/Scripts/check-core.sh
```

This runs generated-contract drift checks, four-language catalog validation and native core checks. New cases cover environment/version validation, leading-zero codes, bearer routing, 401 clearing, cooldown, lost-response replay, account isolation and persist-before-ack ordering. Existing training/recording/units/HR/planning checks remain included.

A dedicated harness tests the actual Swift HTTP client against the real API and PostgreSQL without sending real email or contacting providers. It requires `NODE_ENV=test` and a database whose name ends in `_test`. Its OTP inbox routes exist only in this standalone harness, never in the normal API entry point. Bind its host port only to loopback:

```sh
docker compose --profile test run --detach \
  --name hybrd-native-integration --publish 127.0.0.1:3011:3011 test \
  sh -c 'bun install --frozen-lockfile && bun run db:migrate && bun run db:seed && bun ios/Scripts/backend-test-server.ts'
# Wait for "Isolated native test backend ready" in this container’s logs.
HYBRD_BACKEND_TEST_URL=http://localhost:3011 bash ios/Scripts/check-core.sh
docker stop hybrd-native-integration
docker rm hybrd-native-integration
docker compose --profile test stop postgres-test
```

Use the harness URL only for this isolated test; the suite reads its test inbox and deletes the disposable test identity it creates. The test covers email OTP → bootstrap → device registration → onboarding → profile/units/zones → plan creation/activation → run/lift upload → plan move preserving completed history → Progress/ETag → restart → sign-out. Timing assertions exercise a paused run, absent legacy timing, retained local recording data and absence of fabricated moving time/duplicate laps.

## Device acceptance checklist

1. Real inbox delivery, invalid/expired code, resend cooldown, keyboard/one-time-code autofill and email normalization.
2. New-account onboarding: close/reopen, edit recap, optional body details, zero/high mileage, no provider prompts, no paid entitlement.
3. Save profile and units, sync, accept a starter plan; sign out/in and compare restored values.
4. Log one run and one lift; verify server totals and another installation’s restore without duplicates.
5. Disconnect networking during save; relaunch, reconnect and use Sync now. Review conflicts without silently discarding edits.
6. Switch users/domains and confirm no cross-account plans, credentials, Watch receipts or outbox uploads.
7. Verify an expired session during an active run, reauthenticate into the same account, then save; test Watch delivery on real paired devices.
8. Review light/dark, large text, VoiceOver and translated layouts.

Native executable checks and real Docker-backed requests pass. Bitrig builds the iPhone and Watch targets. Bitrig’s iPhone UI state reader currently fails, so this is not a claim of automated tap-through, real email delivery or physical-device sensor/Watch acceptance.

## Backend follow-up

No new backend endpoint was required for this slice. Before broader rollout, align public-library exercise coverage with the server catalog; extend the workout contract if raw routes, distinct active duration and overlapping native lap kinds must sync losslessly. Zero/high-volume adaptive planning, advanced profile representation, account lifecycle, providers, AI and billing need their own integration/acceptance passes. Preserve the elapsed-duration, idempotency and historical-plan rules in the current [iOS handoff](../docs/ios-handoff.md).
