# Strava integration and iOS handoff

The backend owns OAuth credentials, history retrieval, metric previews, token refresh, webhook handling and outbound publishing. iOS opens authorization, lets the athlete review onboarding suggestions, saves normal workout results, and shows connection/job status. No iOS implementation is included in this change.

The product owner confirmed Strava approval for this use. The implemented history workflow is a bounded import for the connected athlete's onboarding and planning: it does not scrape pages, build a cross-user dataset or train a model. Imported previews are not automatically submitted to the AI providers.

For the next onboarding phase, see the [onboarding → backend handoff](onboarding-backend-handoff.md). Name/weight import and independently usable profile-only previews are requested additions; the current implementation below imports zones and activity history. Strava does not provide documented height/age fields.

## Implementation

1. Connect a Strava account to an authenticated hybrd athlete with one-time, ten-minute OAuth state. Store encrypted tokens only on the server.
2. Queue a durable history job that fetches configured HR zones and the previous 365 days of activity summaries, then selected running best efforts.
3. Expose a reviewable preview. iOS uses accepted values to create a baseline and a planning context through the existing sync contract.
4. Enqueue eligible workout exports in the same PostgreSQL transaction as workout sync. Process them after commit, independently of the phone's lifecycle.
5. Handle token rotation, bounded retries, application-wide request limits, webhook invalidation, disconnect, account deletion and uncertain delivery.

The worker runs inside the API process. PostgreSQL persists jobs and coordinates workers with a session advisory lock. Multiple API processes cannot claim the same job concurrently. No Redis or additional Docker container is needed. A crashed read/refresh job can resume; a publish interrupted after the send boundary requires reconciliation.

## Connect and onboarding

All `/v1` endpoints use the existing hybrd bearer session. Strava is a connected training service, not another sign-in provider.

1. `GET /v1/integrations/strava` returns `available`, connection status, granted scopes, `autoPublish`, an optional history preview, and the 30 most recently updated jobs. Hide/disable connection when `available:false`.
2. `POST /v1/integrations/strava/connect` with `{"autoPublish":true}` returns `authorizationUrl`, `state`, and `expiresInSeconds:600`. Offer the auto-publish choice explicitly. `false` omits the write scope.
3. Open the returned URL using the native Strava/system authentication flow. The provider redirects to the backend's `/integrations/strava/callback`. The backend exchanges the code and returns to the configured app link, by default `hybrd://integrations/strava?status=connected`. Outcomes are `connected`, `cancelled`, or `failed`; no tokens appear in the app link. Register the app URL scheme or an HTTPS universal link. After returning, fetch authenticated status rather than trusting the app-link status as authentication.
4. A successful connection queues history automatically if activity access was granted. Poll status with backoff while a job is `queued`, `running` or `retry`. A summary can arrive before the best-effort detail requests finish.
5. On later onboarding/plan creation, `POST /v1/integrations/strava/history` returns `202 {jobId}`. Concurrent refresh requests reuse the pending job. Existing plans and accepted baselines are never silently overwritten.

An optional native code handoff, `POST /v1/integrations/strava/complete` with `{state,code,scope}`, consumes the same state and is bound to the signed-in athlete. Use it only if the native flow delivers those callback values directly; do not call it after the normal server callback already consumed the state. Each Strava identity has one connected hybrd owner. Disconnect before switching Strava identities.

Requested scopes are `read`, `profile:read_all`, `activity:read_all` and optionally `activity:write`. Users can decline scopes. Missing profile access leaves HR zones unknown; missing write access disables publishing; missing activity access disables history. Reconnect to grant missing permissions.

## Preview semantics

| Field | Meaning |
| --- | --- |
| `heartRateZones` | Strava's configured boundaries and custom/default indicator; `maxBpm:null` means an open upper zone. These are imported settings, not inferred physiological thresholds. |
| `running` | Rolling 7-, 28- and 365-day totals: run count, meters, elapsed/moving seconds, distance-weighted moving pace in seconds/km, average weekly distance and runs/week. |
| `longestRunM` | Longest observed run in the imported period. |
| `strengthSessions` | Count of WeightTraining summaries in the period; no exercise-level PBs are inferred. |
| `observedBestEfforts` | Best returned effort at each distance among inspected runs, with activity ID, date and elapsed time. |
| `bestEffortCoverage` | Number of inspected runs and total runs. `allTimePersonalBests:false` is deliberate. |
| `historyComplete` | Whether paging exhausted activities in the requested period. A bounded import can be incomplete. |
| `missing`, `requiresReview` | Information still needed from the athlete; every preview requires review. |

The import uses a rolling 365-day UTC interval, at most ten pages of 200 summaries. Duplicate IDs, flagged activities and results outside the interval are excluded. Running includes Run, TrailRun and VirtualRun. Empty windows report zero volume and unknown pace, not an invented performance estimate.

Strava has no single running all-time PB endpoint. The worker inspects up to three promising non-manual runs for each of 1 km, mile, 5 km, 10 km, half marathon and marathon (at most 18 distinct detail requests). This can miss a faster effort hidden within another run or outside the year. Display these as observed best efforts and allow manual correction; never label them verified all-time PBs. Do not infer goals, availability, equipment or strength PBs from activity summaries.

For accepted onboarding values, sync `baseline_snapshot` with `source:"strava"` (or `mixed` when combined with other inputs), period dates, `metrics`, `confidence`, and `confirmedAt`. Store source/coverage and reviewed status in the allowed feature data. Create a new `planning_context_snapshot` referencing the baseline. The existing immutable snapshot and explicit plan-acceptance behavior still applies. Preview data is separate from canonical workout history: do not sum its totals with overlapping HealthKit or hybrd workouts.

## Automatic outbound sync

Normal `workout_result` sync enqueues publication when Strava is connected, auto-publish is enabled, the source is `manual` (the existing contract for hybrd-recorded results), and completion is `completed`, `partial` or `modified`. HealthKit imports, skipped/abandoned workouts, rejected mutations and rolled-back transactions do not publish. Sync replay, result updates and additional physical result IDs for the same logical workout do not create another export.

Supply actual `startedAt`, IANA `timezone` and positive elapsed `durationS` (or the running duration). Missing timing produces `needs_details` with `WORKOUT_EXPORT_INCOMPLETE`; a corrected workout sync requeues it. Never substitute the upload time for the workout start. Running exports include distance; strength exports use `WeightTraining`.

**This MVP creates Strava summary activities.** The current canonical API does not ingest GPS/HR streams or FIT/TCX files, so the export cannot include a route, per-sample HR, laps or strength sets. Existing published activities are not automatically edited or deleted when local records change. A correction of an already published workout should be made on Strava. Files/streams and remote update/delete propagation would require additional contracts.

The queue commits before calling Strava. Successful exports store a remote activity ID. A 429 is retried after a delay; expired tokens are refreshed with rotation. Network/5xx errors after sending a creation request, malformed success responses or process death at the send boundary can mean Strava accepted the workout. Those jobs enter `needs_review` and **are never blindly reposted**. The create-activity endpoint does not provide a documented idempotency key.

`POST /v1/integrations/strava/jobs/{jobId}/retry` safely retries eligible failed/deferred jobs, but rejects uncertain delivery. To associate an activity already visible on Strava, use `/jobs/{jobId}/reconcile` with `{"remoteActivityId":"123456789"}`. The worker fetches it using this athlete's connection and verifies the exact hybrd workout reference in its description before marking it published. A mismatch remains `needs_review`. If no activity exists, leave the uncertain job for review; this API intentionally has no force-repost operation. Strava IDs are decimal strings throughout the client contract.

`PATCH /v1/integrations/strava` with `{"autoPublish":false}` stops pending exports; enabling it affects subsequent workout saves and does not backfill old workouts. An already sent request can finish. `DELETE /v1/integrations/strava` stops new work, clears the preview, cancels pending imports/exports and queues grant revocation. Status moves from `disconnecting` to `disconnected`; wait for revocation before reconnecting. It does not delete activities already posted on Strava.

## Configuration and Docker

Leave the optional fields empty for ordinary development; status reports unavailable and the worker makes no external calls. Configure these outside source control for live testing:

```dotenv
STRAVA_CLIENT_ID=your_numeric_app_id
STRAVA_CLIENT_SECRET=your_app_secret
STRAVA_APP_RETURN_URL=hybrd://integrations/strava
STRAVA_WEBHOOK_SECRET=a_random_url_safe_secret_at_least_32_characters
STRAVA_WEBHOOK_VERIFY_TOKEN=a_separate_random_verification_token
STRAVA_WEBHOOK_SUBSCRIPTION_ID=
```

Set `BETTER_AUTH_URL` to the public HTTPS API origin and register its host in Strava's application callback domain. The callback URL is `${BETTER_AUTH_URL}/integrations/strava/callback`; the Strava webhooks callback is `${BETTER_AUTH_URL}/webhooks/strava/${STRAVA_WEBHOOK_SECRET}`. The phone return link is separately controlled by `STRAVA_APP_RETURN_URL` and cannot be supplied by a request.

Create the app's Strava push subscription using the configured callback and verify token, following the official webhook documentation. Initial GET verification works before a subscription ID exists. Save the returned numeric ID in `STRAVA_WEBHOOK_SUBSCRIPTION_ID`, then restart the API; POST delivery is rejected until that ID matches. No live subscription or provider credentials are provisioned automatically. Strava allows one subscription per application, so use separate apps for isolated environments or route events deliberately.

`make up` applies migration 0005 and starts the API and PostgreSQL. Email delivery uses Resend when configured; no local mail container is required. The API process starts the Strava worker only with configured client credentials. `make check` runs mocked provider tests and isolated real PostgreSQL tests; it never contacts Strava. `make build` produces the same production API image with the worker included.

## Retention and operations

Tokens use AES-256-GCM with per-athlete authenticated data and a key derived from `BETTER_AUTH_SECRET`. Keep that secret stable; changing it without re-encrypting tokens requires reconnecting accounts. Status, canonical sync, account exports, logs and app redirects never contain provider credentials.

History previews expire after seven days. Expired previews are hidden immediately and purged by the worker, along with old temporary import state and webhook receipts. Activity create/update/delete events invalidate cached previews and pending imports, then queue a fresh summary. Duplicate events are recorded once. Deauthorization clears tokens and previews and cancels pending work. Webhook handling performs only database work before acknowledgment. Strava does not sign these event payloads: the high-entropy callback path and expected subscription ID protect ingestion. Keep callback URLs out of proxy access logs and analytics.

Account deletion purges connection/history/jobs with the athlete. An encrypted revocation outbox containing only the former opaque athlete UUID and token envelope survives until provider revocation succeeds, at most seven days. Backups follow the infrastructure retention policy. Accepted user-reviewed canonical baselines remain ordinary immutable training records until account deletion; ephemeral provider previews do not replace that history.

The persisted application-wide limiter reserves conservatively below default Strava limits: 80 requests/15 minutes and 800/day, including OAuth and refresh. 429 responses defer jobs. Each worker pass makes a bounded number of calls with ten-second network timeouts. Observe sanitized `strava_worker_error` / `strava_revocation_retry` logs and connection/job states. Live acceptance still needs a real approved application: authorize with partial/full scopes, import known history, record one run/strength workout, verify visibility/values on Strava, exercise webhook delivery, and disconnect.

Official references: [OAuth](https://developers.strava.com/docs/authentication/), [API reference](https://developers.strava.com/docs/reference/), [webhooks](https://developers.strava.com/docs/webhooks/), [rate limits](https://developers.strava.com/docs/rate-limits/).
