# Deployment and operations

No service has been provisioned or deployed. The production image and `railway.json` target one API instance plus PostgreSQL. `make build` builds the non-root image with locked production dependencies, SQL migrations and Apple's public StoreKit trust root.

## Configure and release

1. Use the repository root build context, `server/Dockerfile`, Railway PostgreSQL's private `DATABASE_URL`, `NODE_ENV=production`, a random `BETTER_AUTH_SECRET`, HTTPS `BETTER_AUTH_URL`, exact trusted origins and `DEV_AUTH_ENABLED=false`.
2. Configure Google and Apple OAuth clients and Resend email OTP delivery as detailed in [authentication.md](authentication.md). Use `AUTH_EMAIL_TRANSPORT=resend`, a verified `AUTH_EMAIL_FROM`, and `RESEND_API_KEY`. The same Resend delivery path is used in development. Rotate Apple's client-secret JWT before expiration. Configure StoreKit independently with `STOREKIT_BUNDLE_ID`, production numeric `STOREKIT_APP_APPLE_ID`, `STOREKIT_ENVIRONMENT=Production`, `STOREKIT_ROOT_CERTIFICATES=certificates/AppleRootCA-G3.cer`, and `STOREKIT_PRODUCTS` mapping your real auto-renewable product IDs to `pro`.
3. Configure App Store Server Notifications V2 to POST to `/webhooks/apple`. The endpoint verifies the notification and nested transaction/renewal signatures. Keep sandbox and production environments separate.
4. Set `OPENROUTER_API_KEY`, `OPENROUTER_LLM_MODEL` to a model supporting strict structured JSON, and the configured Jev alias. AI consent, entitlement, policy and persisted quotas still apply. Verify your provider data-retention arrangement before public release; the coach requests providers that deny data collection. The Jev Decisions endpoint has its own provider contract.
5. For push, mount the `.p8` key outside source control and configure `APNS_PRIVATE_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`. Each installation records its actual APNs environment. Local scheduled reminders remain on-device.
6. Railway applies migrations as a serialized pre-deploy job, starts the API, and checks `/health/ready`. Production startup never modifies schema. `bun run ops seed-catalog` loads versioned reference data without creating users.
7. Publish a reviewed policy JSON with `bun run ops publish-policy /absolute/path/policy.json`. Format: `{"config":{...PolicyConfig...},"minimumAppVersion":"1.0.0"}`. The command validates bounds, allocates a version under a lock and retires the previous publication. Existing plan references remain immutable. The development policy is only an example, not a reviewed training prescription.
8. Run native Google/Apple login, real email OTP delivery/sign-in and sandbox purchase/renewal/restore/refund, AI-response quality, real-device push and full device-restore acceptance tests before launch.

The process has 60-second HTTP idle timeouts and drains for up to 35 seconds on shutdown. Allow 40 seconds before termination. Metadata-only JSON logs include request ID, matched route, status and duration; no auth headers, prompts, messages or health payloads. Configure infrastructure alerts for readiness failure, elevated 5xx/latency, database storage and provider billing. General API/auth/webhook limits are process-local; AI quotas are persistent. Revisit general rate limits before scaling beyond one API instance.

## Operator commands

Run inside the API container with `docker compose exec api bun run ops ...`, or in the deployed image with equivalent environment variables:

```sh
bun run ops seed-catalog
bun run ops publish-policy /absolute/path/policy.json
bun run ops prune-operational-data
bun run ops notify AUTH_USER_ID DEVICE_UUID DELIVERY_UUID sync_hint
```

`notify` is an explicit operator action, with idempotency by delivery UUID. It sends either a generic `coach_ready` alert or a background `sync_hint`; it never includes training data. There is no public notification-send API. APNs errors invalidate only the token that actually failed, leaving sync registration intact. Retry a failed delivery with a new UUID only after inspecting its outcome; an unknown transport outcome may already have delivered.

Run `prune-operational-data` daily through deployment operations. No separate worker service or Redis is required. Strava runs its durable job processor inside the API process when configured. It removes compact AI context after 30 days and response cache copies after 90 days while retaining training history, canonical conversations, quota metadata and replay protection. No scheduler is installed automatically.

## Backup and recovery

Enable managed PostgreSQL backups/PITR appropriate to your retention policy before taking real user data. Verify restorations in an isolated database, run migrations/readiness and the API smoke flows there, then switch the API connection only after checking consistency. Example logical backup/restore tools are `pg_dump --format=custom` and `pg_restore --no-owner`; keep credentials in environment/config, encrypt backup storage, and do not commit dumps. Test restoration periodically and after schema changes. If a backup predates a device cursor, pull returns `CURSOR_AHEAD`; rebuild that local replica from cursor zero. Restoring deleted accounts from old backups requires replaying deletion records from your operational process before exposing the restored database.

Account deletion hard-purges the live database. Backups expire according to infrastructure retention; configure and disclose that period. Deletion does not cancel Apple subscriptions. No actual production backups, monitoring or provider credentials are created by this repository.

## Strava

Configure the approved Strava application, public callback, phone return link and webhook subscription using [strava-integration.md](strava-integration.md). Tokens remain encrypted server-side. The API's built-in worker handles history, publication, revocation, expiry and retries through PostgreSQL; no additional Compose service is required. Account deletion retains only an encrypted grant-revocation envelope for up to seven days, normally removed after the next worker pass. Complete the documented live-provider acceptance before release.
