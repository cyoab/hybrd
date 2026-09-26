# hybrd native app

The official source of truth is this repository's `ios/` directory.

## Layout

- `Project.json`: Bitrig/XcodeGen project definition; separate iPhone and Apple Watch targets.
- `App/`: SwiftUI account flow, backend replicas/outboxes, workout logging, and read-only access to legacy SwiftData recordings.
- `Watch/`: standalone run recording within the paired companion, with cached prescriptions, live metrics, interval controls and durable result transfer.
- `Shared/`: typed local models, starter-plan rules, and WatchConnectivity transport.
- `Tests/`: executable checks for planning, profile validation, backward compatibility, and the bundled catalog.

The current Bitrig-managed workspace links its `App`, `Watch`, `Shared`, and `Project.json` paths here. These are local development links, not copies of the source. Build outputs remain in Bitrig's build directory.

## Current scope

The app requires an account: signed-out launches show the welcome page, while signed-in launches restore onboarding or the athlete’s real training data. There are no seeded workout plans, anonymous exploration or profile preview controls. See [BACKEND-INTEGRATION.md](BACKEND-INTEGRATION.md) for server/version settings, Docker setup, supported flows and acceptance checks.

Existing pre-account SwiftData recordings remain available as a read-only local archive under Account & sync, without mixing them into account data. Sample workout fixtures exist only in Tests. New accounts start with an empty plan; starter prescriptions require review and acceptance.

The athlete profile includes optional birth date/age, height, weight, self-reported running and strength experience, editable personal BPM boundaries, running PRs, and strength records expressed as load × reps. Native illustrated selectors cover ten muscle groups and twenty equipment types. A bundled public-domain catalog contains 876 exercises as an internal data source. It is not a profile destination; strength PR entry uses a focused movement picker. Profile saves preserve plan snapshots, actual results, and unfinished logs. Applying training preferences to a new starter block still requires review and acceptance.

Apple Health import requests read-only access to date of birth, height, and weight, then presents a per-field review before applying values to the profile draft. It does not import heart-rate zones or PRs. Strength records can also be selected from completed sets in local logs. Email authentication and manual onboarding are connected. Provider import controls are hidden in connected testing; native Strava OAuth/import review remains deferred. See `BACKEND-ONBOARDING.md` and `../docs/onboarding-api.md`.

Both app targets have workout HealthKit permissions; outdoor runs request precise location when recording starts. Physical-device Health verification still needs a connected Apple account and provisioned app identifier in Bitrig. Authenticated routing, manual onboarding and core server synchronization are implemented for testing. Automatic BPM calibration, cloud AI, StoreKit, WorkoutKit plan delivery and production/provider acceptance remain follow-up work; see `BACKEND-INTEGRATION.md`. Native run recording uses GPS and live Apple Health metrics; strength logging stores weight, reps, optional RIR, and persistent rest timers with opt-in local alerts. See `WORKOUT-RECORDING.md` for behavior and hardware validation requirements. The current local models are not the generated OpenAPI contract. The starter generator uses a small reviewed recipe library: configured equipment constrains movement choices and selected muscles influence their order. Age, body measurements, experience, and PRs are stored metadata; they do not yet calculate loads or progression. Goal-specific programming and adaptive progression remain future work.

## Integration constraints

Follow `../docs/ios-handoff.md`; regenerate the scoped Swift wire models from `../contracts/openapi.yaml` with `Scripts/generate-onboarding-wire.py` when the contract changes.

- Restore new devices from cursor `"0"`; retain revision/cursor values as decimal strings.
- Atomically persist pulled entities and the cursor, then acknowledge.
- Durable outbox entries retain UUID idempotency keys across transport retries.
- Preserve prescribed and actual workout data separately.
- Retain immutable plan snapshots and compare the expected active head on activation.
- Require explicit plan acceptance; preserve separate consent and entitlement gates for future AI/provider/billing operations. Basic onboarding/profile/sync do not require paid access.
- Keep tokens in Keychain and provider secrets on the server.

## Design implementation

The user's supplied reference at `../docs/design.png` is the visual direction: a light neutral canvas, black primary controls, restrained orange accents, a week selector, day-specific workout cards, and three primary tabs: Plan, Progress, and Coach. The Plan home keeps the weekly calendar with horizontal week paging and adds colorful logged-progress tiles and illustrated workout cards; workout flows use the same palette. See `DESIGN.md` for tokens, accessibility choices, and references from Runna, Hevy, Duolingo, Revolut, Headspace, and Lifesum. The account app currently uses Plan and Progress tabs; the previous Today tab has been removed.

## Local checks

Run the core checks from this directory:

```sh
bash Scripts/check-core.sh
```

Build and run the iPhone and Watch targets using Bitrig.

## Validation at scaffold handoff

- Bitrig build completed successfully for the iPhone app and embedded Watch target.
- Core executable checks additionally cover legacy profile decoding, richer profile round trips, optional and invalid input, HR boundary ordering, PR parsing, completed-set candidates, equipment-constrained starter recipes, focus ordering, and catalog integrity. An isolated in-memory SwiftData check exercised the actual profile-save implementation, confirming reload persistence, unchanged plans/results/drafts, and rejection of stale or invalid edits.
- Existing core executable checks passed for calendar paging across daylight-saving and year boundaries, distant date jumps, weekly actual-versus-planned totals, localized weekly-distance entry, invalid numeric input, chronological work/recovery timelines, session composition totals and proportions, HR-zone decoding and history-preserving plan upgrades, legacy target fallback, availability, physical/logical identities, historical snapshot preservation, schedule conflicts, unperformed defaults, encoding, old draft decoding, interval totals, partial and extra sets, actual-result validation, and pause/resume timing.
- Home, session, and athlete-profile components were visually reviewed using offscreen SwiftUI renders in light, dark, compact, and accessibility layouts with the bundled illustrations. This was a macOS rendering harness, not interactive iPhone verification.
- Bitrig reports both simulators running, but its simulator-inspection tool returns that this destination does not support simulator state. Interactive UI behavior and paired Watch delivery have not been verified.

### Measurement preferences

Open **Athlete profile → Units**, choose **kg / lb** and **km / miles** independently, and tap **Save profile**. Preferences apply to entries, pace, charts, history and the synced Watch plan. Older data defaults to kg/km. Actual measurements stay in canonical kg/meters, so changing units preserves the original training data. New runs use the selected distance unit for automatic splits; an already-started run keeps its split interval.

## Languages

English, Spanish, Brazilian Portuguese, and French are bundled for iPhone and Apple Watch. Language follows the device/per-app preference, with English fallback; unit choices stay independent. See [LOCALIZATION.md](LOCALIZATION.md) for the resource workflow, coverage, and checks.
