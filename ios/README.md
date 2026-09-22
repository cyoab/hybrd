# hybrd native app scaffold

The official source of truth is this repository's `ios/` directory.

## Layout

- `Project.json`: Bitrig/XcodeGen project definition; separate iPhone and Apple Watch targets.
- `App/`: SwiftUI iPhone shells, SwiftData persistence, draft logging, local sample plan, and deterministic coach fallback.
- `Watch/`: read-only companion shell for receiving and browsing prescriptions.
- `Shared/`: typed local models, starter-plan rules, and WatchConnectivity transport.
- `Tests/`: focused executable checks for local planning invariants.

The current Bitrig-managed workspace links its `App`, `Watch`, `Shared`, and `Project.json` paths here. These are local development links, not copies of the source. Build outputs remain in Bitrig's build directory.

## Current scope

This is an early local scaffold, not the complete MVP. It includes sample data, editable goals, heart-rate-zone run targets, four-week starter prescriptions and a clearly labeled sample block, local SwiftData snapshots, draft run/strength entry, immutable local plan history, a deterministic on-device coach, basic totals, and a read-only Watch companion.

Personal BPM calibration and live heart-rate recording are not available. No backend requests, authentication, cloud AI, entitlements, HealthKit import, StoreKit, reminders, WorkoutKit delivery, or production synchronization are implemented. The current local models are not the generated OpenAPI contract. The starter generator is deliberately simple; goal-specific programming, priority weighting, robust scheduling, and adaptive progression are future work.

## Integration constraints

Follow `../docs/ios-handoff.md` and generate the production API client from `../contracts/openapi.yaml` before implementing network integration.

- Restore new devices from cursor `"0"`; retain revision/cursor values as decimal strings.
- Atomically persist pulled entities and the cursor, then acknowledge.
- Durable outbox entries retain UUID idempotency keys across transport retries.
- Preserve prescribed and actual workout data separately.
- Retain immutable plan snapshots and compare the expected active head on activation.
- Require consent, entitlement, proposal review, and explicit acceptance before cloud changes.
- Keep tokens in Keychain and provider secrets on the server.

## Design implementation

The user's supplied reference at `../docs/design.png` is the visual direction: a light neutral canvas, black primary controls, restrained orange accents, a week selector, day-specific workout cards, and three primary tabs: Plan, Progress, and Coach. The Plan home and workout flows now use this direction. See `DESIGN.md` for tokens, accessibility choices, and references from Runna, Hevy, Duolingo, Revolut, Headspace, and Lifesum. The iPhone app uses Plan, Progress, and Coach tabs; the previous Today tab has been removed.

## Local checks

Run the core checks from this directory:

```sh
swiftc -module-cache-path /tmp/hybrd-swift-module-cache Shared/TrainingProfile.swift Shared/TrainingWorkout.swift Shared/TrainingPlan.swift Shared/WorkoutResult.swift Shared/TrainingEngine.swift Shared/SampleTraining.swift Shared/RunTimeline.swift Shared/SessionBreakdown.swift Shared/HeartRateZone.swift Shared/HeartRatePlanUpgrade.swift Tests/TrainingEngineChecks.swift -o /tmp/hybrd-core-checks
/tmp/hybrd-core-checks
```

Build and run the iPhone and Watch targets using Bitrig.

## Validation at scaffold handoff

- Bitrig build completed successfully for the iPhone app and embedded Watch target.
- Core executable checks passed for localized weekly-distance entry, invalid numeric input, chronological work/recovery timelines, session composition totals and proportions, HR-zone decoding and history-preserving plan upgrades, legacy target fallback, availability, physical/logical identities, historical snapshot preservation, schedule conflicts, unperformed defaults, encoding, old draft decoding, interval totals, partial and extra sets, actual-result validation, and pause/resume timing.
- Session infographic components were visually reviewed using offscreen SwiftUI renders in light, dark, compact, and accessibility layouts with the bundled illustrations. This was a macOS rendering harness, not interactive iPhone verification.
- Bitrig reports both simulators running, but its simulator-inspection tool returns that this destination does not support simulator state. Interactive UI behavior and paired Watch delivery have not been verified.
