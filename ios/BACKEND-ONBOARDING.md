# Native onboarding API integration

The data layer is now connected to email sign-in and the manual onboarding UI. See [Email and core backend integration](BACKEND-INTEGRATION.md) for configuration, Docker tests, recovery, scope and remaining acceptance checks. The backend contract is [onboarding-api.md](../docs/onboarding-api.md); `contracts/openapi.yaml` remains the wire source of truth.

## Included

- `BackendWire.swift`: generated Codable models for onboarding state/drafts/completion, Health/Strava import decisions, independent Strava previews, and catalog responses. Required nullable fields encode as JSON null; schema versions and fixed enum values decode strictly. Open-ended catalog metadata is separate from typed answers.
- `OnboardingAPIClient`: authenticated GET state/catalog/Strava, read-only Strava connect, history refresh, and save/complete requests. It sends `autoPublish:false`, handles 202 history responses, propagates structured errors and Retry-After, and passes rotated session tokens to the caller's storage callback.
- `RemoteOnboardingStore`: one account/environment's restore/save/complete state with an atomic request journal. Request body and UUID key are saved before sending, and retained after network errors, cancellation, or unsuccessful responses. Explicit retries resend identical bytes and keys. Conflicts preserve pending answers for review; they are not automatically rebased or dropped.
- `OnboardingDraftAdapter`: deliberate one-way mapping of a reviewed, complete **manual** preview to canonical units, stable goal/experience codes, all 20 equipment slugs, ten muscle slugs, and Foundation weekday numbering. Missing/ambiguous catalog mappings fail rather than silently dropping selections. The caller supplies the actual baseline reference period.
- `BackendDay`, `BackendInstant`, and `BackendRevision`: dates stay calendar dates, timestamps retain their original offset/precision, and revisions remain decimal strings through the PostgreSQL bigint maximum.

`ConnectedDraftMapping` now restores the representable manual fields into an account-scoped editor while retaining the full original wire draft. It preserves untouched DOB/provenance, records, HR ranges and fractional strength frequency. Provider import decisions block manual-only editing until a future consent/review flow can handle them. Anonymous preview flags or sample data never authenticate a user or become an upload automatically.

`BackendAppController` restores bootstrap/device/catalog/policy and canonical sync before opening the account’s journey. Each confirmed step saves with the server revision; recap completion uses a durable request key and pulls canonical data afterward. The four-second animation waits for successful completion. Setup completion is not plan activation or paid entitlement. Plan review/acceptance is separate.

For a lost response, `retryPending()` reuses exact request bytes and UUID. Revision conflicts keep local and server answers for review. Completion retry can recover the receipt through GET. The receipt’s sequence stays a hint; the existing pull cursor advances only through committed pull pages. `OnboardingAPIClient` retains provider endpoint support as an unused foundation, but the current UI never invokes it.

The HTTP transport uses an ephemeral, cookie-free session and declines redirects so credentials cannot follow a changed destination. HTTPS is required outside an explicit DEBUG localhost origin. Physical-device development should use a configured reachable HTTPS origin. ATS settings and provider callback URL registration are not changed by this layer.

The journal persists only typed state and pending domain request bodies, never session/provider tokens. It uses an environment hash and athlete ID in its filename, atomic writes, restrictive permissions, iOS complete file protection, and backup exclusion. Protected data being unavailable is an error; no request is sent before its journal is durable. Corrupt or unsupported cache data is preserved rather than silently replaced. Account deletion and explicit local-data removal must delete that account's journal as part of the future account lifecycle implementation.

## Regeneration and validation

Run from the repository root:

```sh
python3 ios/Scripts/generate-onboarding-wire.py
bash ios/Scripts/check-core.sh
```

The scoped generator reads checked-in OpenAPI through macOS's system Ruby/Psych. It needs no network/package install, embeds the source checksum, and fails on unsupported schema constructs. `--check` detects drift and is part of core checks. It now covers onboarding and core bootstrap/catalog/policy/sync/profile/plan/result/progress transport shapes, not server-side range/cross-field validators. One explicit tightening is documented in the generator: the reused OpenAPI draft component is nullable for GET, but a save request must contain a nonnull draft as required by the route implementation.

Native tests decode and round-trip the backend's checked-in request example, retain mixed import provenance/fractional frequency/zones, decode independent partial Strava previews, validate lossless dates/revisions, map every equipment/focus option, and exercise errors, account changes, durable lost-response replay, restart recovery, conflict preservation and unsupported-planning receipts. Existing training/profile/localization/workout regressions also pass. Bitrig builds pass for iPhone and Watch.

Email auth and core requests now also pass a live Swift → Docker/PostgreSQL test with injected email delivery. The connected screens build for iPhone and Watch. Real inbox delivery, automated native tap-through, provider callbacks, Health imports, purchases and paired physical-device acceptance remain separate checks. See [the testing guide](BACKEND-INTEGRATION.md).
