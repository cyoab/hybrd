# Native onboarding API adapter

Implemented against backend commit `7df08e5` and the [connected onboarding contract](../docs/onboarding-api.md). This is the native data/transport layer, **not a live connected sign-up screen**. The app's existing onboarding preview remains isolated from accounts, training history, and billing.

## Included

- `BackendWire.swift`: generated Codable models for onboarding state/drafts/completion, Health/Strava import decisions, independent Strava previews, and catalog responses. Required nullable fields encode as JSON null; schema versions and fixed enum values decode strictly. Open-ended catalog metadata is separate from typed answers.
- `OnboardingAPIClient`: authenticated GET state/catalog/Strava, read-only Strava connect, history refresh, and save/complete requests. It sends `autoPublish:false`, handles 202 history responses, propagates structured errors and Retry-After, and passes rotated session tokens to the caller's storage callback.
- `RemoteOnboardingStore`: one account/environment's restore/save/complete state with an atomic request journal. Request body and UUID key are saved before sending, and retained after network errors, cancellation, or unsuccessful responses. Explicit retries resend identical bytes and keys. Conflicts preserve pending answers for review; they are not automatically rebased or dropped.
- `OnboardingDraftAdapter`: deliberate one-way mapping of a reviewed, complete **manual** preview to canonical units, stable goal/experience codes, all 20 equipment slugs, ten muscle slugs, and Foundation weekday numbering. Missing/ambiguous catalog mappings fail rather than silently dropping selections. The caller supplies the actual baseline reference period.
- `BackendDay`, `BackendInstant`, and `BackendRevision`: dates stay calendar dates, timestamps retain their original offset/precision, and revisions remain decimal strings through the PostgreSQL bigint maximum.

Connected drafts remain in the generated wire model; do not round-trip them through the current preview model. The preview cannot represent every server field, notably fractional strength frequency, fractional HR ranges, DOB provenance, records and import decisions. Restoring into it would lose data. The adapter therefore does not offer a lossy reverse conversion or overwrite a server draft with anonymous answers.

## Caller integration sequence

1. Configure an API origin and implement email/social authentication and environment/account-scoped Keychain storage. The client requires the bootstrap **athlete UUID**, which is different from auth user ID. It does not create identities or hold credentials on disk.
2. Register the installation, restore canonical data through the existing pull/ack protocol, then construct `BackendAccountScope`, `OnboardingAPIClient`, and `RemoteOnboardingStore` for that account. Call `restore()` regardless of anonymous preview completion flags.
3. Provide a credentials closure that returns the currently authenticated scope/token, and a token-rotation callback that updates the matching Keychain session. The client checks account identity before sending and after awaiting a response. Replace the account's store/view state on logout or switching; do not display an old store while authenticating another athlete.
4. Read `state`, `hasPendingRequest`, and `pendingDraftForReview`. For a new account, let the athlete explicitly review attaching any manual preview before invoking the one-way adapter. For a restored server draft, edit the full wire draft so fields unsupported by the old preview are preserved.
5. Use `saveReviewedDraft(_:step:)`. Do not create a second save while an unresolved request exists. Use `retryPending()` after recoverable failures, honoring exposed retry delays. For conflicts, fetch state and show both server and pending answers, then call `discardPendingAfterReview()` only after resolving the pending work; the corrected save gets a new key.
6. On recap confirmation, invoke `completeReviewedDraft(deviceID:catalogVersion:policyID:)`. Completion uses the last saved revision and blocks known import-review issues. A lost completion response can be replayed after relaunch. `ONBOARDING_ALREADY_COMPLETED` triggers receipt recovery through GET.
7. Pull from the existing sync cursor after completion. The receipt's `latestSequence` stays a hint. A receipt does not grant membership, create a plan, or activate it; inspect `planning.status`, then handle local planning, StoreKit and explicit plan acceptance separately.

The HTTP transport uses an ephemeral, cookie-free session and declines redirects so credentials cannot follow a changed destination. HTTPS is required outside an explicit DEBUG localhost origin. Physical-device development should use a configured reachable HTTPS origin. ATS settings and provider callback URL registration are not changed by this layer.

The journal persists only typed state and pending domain request bodies, never session/provider tokens. It uses an environment hash and athlete ID in its filename, atomic writes, restrictive permissions, iOS complete file protection, and backup exclusion. Protected data being unavailable is an error; no request is sent before its journal is durable. Corrupt or unsupported cache data is preserved rather than silently replaced. Account deletion and explicit local-data removal must delete that account's journal as part of the future account lifecycle implementation.

## Regeneration and validation

Run from the repository root:

```sh
python3 ios/Scripts/generate-onboarding-wire.py
bash ios/Scripts/check-core.sh
```

The small scoped generator reads checked-in OpenAPI through macOS's system Ruby/Psych. It needs no network/package install, embeds the source checksum, and fails on unsupported schema constructs. `--check` detects drift and is part of core checks. It generates transport shapes, not server-side range/cross-field validators. One explicit tightening is documented in the generator: the reused OpenAPI draft component is nullable for GET, but a save request must contain a nonnull draft as required by the route implementation.

Native tests decode and round-trip the backend's checked-in request example, retain mixed import provenance/fractional frequency/zones, decode independent partial Strava previews, validate lossless dates/revisions, map every equipment/focus option, and exercise errors, account changes, durable lost-response replay, restart recovery, conflict preservation and unsupported-planning receipts. Existing training/profile/localization/workout regressions also pass. Bitrig builds pass for iPhone and Watch.

Live auth, Docker-backed end-to-end native requests, OAuth callbacks, real Health reads, connected review UI, account-store hydration, purchase/plan activation and physical-device acceptance are **not validated by these injected-transport tests**. Provider credentials and those native integrations remain required. No services or accounts were started/created for this change, and no existing user data was uploaded.
