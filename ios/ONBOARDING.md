# Onboarding preview

The iPhone sign-up entry now opens a local, resumable athlete journey ending in a membership preview. This is deliberately disconnected from account creation, plan generation, Apple Health, Strava, StoreKit, and the backend.

## Try it

- On first launch, choose **Create account**. **Explore the app** opens the existing app without completing setup.
- After entering the app, open **Athlete profile → Try sign-up & onboarding** to replay it.
- Close a question to return to the welcome screen; **Continue setup** resumes the saved step.
- **Start over** clears only the onboarding draft after confirmation. The live athlete profile, unit preferences, plans, workout recordings, and training history remain unchanged.
- **Sign in**, **Restore purchases**, **Terms**, and **Privacy** explain the preview boundary. They do not pretend to authenticate, restore an entitlement, or accept a subscription agreement.

## Journey

1. Preferred name.
2. Running and strength goals, with an optional race date.
3. Balance between disciplines.
4. Running experience and recent weekly distance, including zero.
5. Lifting experience and current frequency.
6. Optional age, weight, and height.
7. Available weekdays, desired lifting frequency, and session length.
8. Gym presets and an illustrated equipment selection.
9. Illustrated muscle priorities, or a balanced focus.
10. Readiness and an optional context note.
11. Preferences for connecting Health and Strava later; no permission prompts.
12. Personal recap with direct editing of every answer group.
13. Annual/monthly membership selection, followed by a clearly identified preview completion.

Progress indicates actual position; there are no simulated AI generation delays or invented performance promises. Answers can be edited from the recap and returned directly to it. Body details can be skipped.

## Membership presentation

The user confirmed USD prices:

| Option | Total | Supporting comparison |
| --- | --- | --- |
| Monthly | US$10.99 each month | Flexible monthly commitment |
| Annual | US$99.99 each year | Approximately US$8.33/month; 24% less than twelve monthly payments |

Annual is initially selected. Total charge and billing interval remain prominent. The copy explicitly states that this is a preview, no charge occurs, and no free trial is included. Completing the screen saves only the selected offer and the local preview-completion flag. It does **not** grant a subscription entitlement.

## State and integration boundary

- `OnboardingDraft` contains typed goals, experience, preferences, optional body details, and selected membership.
- `OnboardingStore` owns navigation, validation, review mode, and versioned persistence under `hybrd.onboarding.preview.v1` in UserDefaults.
- The store never reads or writes `TrainingStore` or billing/authentication state. `AppEntryView` preserves access to an active or recovered run.
- Display units are independent of the live athlete settings. Distance and body-weight conversions retain exact canonical quantities while toggling; clearing a field invalidates the previous conversion baseline.
- An unreadable saved preview is preserved until an explicit restart. Restart also leaves unrelated UserDefaults values intact.
- Running baseline accepts 0–250 km/week. This describes the athlete's recent activity; it is not the existing local planner's 3–150 km prescription target. A future planner must handle zero and higher-volume baselines deliberately rather than clamping them silently.
- Copy is included in English, Spanish, Brazilian Portuguese, and French, including native plural handling.

Before production, replace the preview entry with authenticated routing, explicitly confirm applying the reviewed draft to an athlete, and support idempotent draft submission. Do not treat `completed` or `enteredApp` as authentication or entitlement signals. Plan creation must use reviewed canonical values and account for stated limitations. Integrate Health/Strava only after separate explicit consent and review of imported values.

Real memberships need App Store Connect products, StoreKit product-provided prices and billing periods, verified transactions/entitlements, pending/canceled/error handling, restore behavior, and final terms/privacy URLs. The hard-coded USD preview is not a production pricing source. Nothing in this change provisions products or starts payments.

## Validation

`bash ios/Scripts/check-core.sh` covers validation, zero/high mileage, repeated unit conversions, cleared-input conversion, all step transitions, recap editing, persistence/resume, isolated restart, corrupt draft recovery, USD offer math, and four-language formatting. The existing workout, profile, progress, and localization regression checks also pass.

Bitrig builds pass for the configured iPhone/Watch project. The welcome screen was inspected in the native iPhone preview. Isolated SwiftUI layout fixtures were reviewed in light/dark appearance and at narrow widths; these supplement rather than replace iPhone interaction testing. The current Bitrig iPhone automation reports that simulator state is unsupported, and native automation taps fail with `noWindowsAvailable`, so a complete automated tap-through and native keyboard/VoiceOver/Dynamic Type checks remain unverified.

Suggested device review:

- Finish a new-user journey with zero mileage and skipped body details.
- Enter 70 km directly, toggle miles and back, clear the field, switch units, and enter another value.
- Close/reopen mid-flow, edit the name and balance from the recap, then restart.
- Try both memberships; confirm completion leaves the live athlete and workout history unchanged.
- Review long names, translated copy, keyboard visibility, large text, VoiceOver, light/dark appearance, and small phones.

## Design references

Mobbin examples were inspected for visual and interaction patterns. Mobbin does not establish conversion performance, so these are design references rather than evidence of commercial success.

- [Runna onboarding](https://mobbin.com/flows/1689d6d5-e245-4369-9dae-320bd863136b): visible progression and focused training questions.
- [Lifesum onboarding](https://mobbin.com/flows/f373ce15-3f4e-4d88-aa24-365969ad35eb): personal framing and an explanation for requested information.
- [Fitbod equipment setup](https://mobbin.com/flows/abb27037-2edf-4e72-9e60-3cb5dbfcc435): equipment selection with visual recognition.
- [Runna membership](https://mobbin.com/screens/3fa764cd-6481-433f-bfc3-63c15c5f09da): benefits and clear plan comparison; its trial offer is not copied.
- [Duolingo membership](https://mobbin.com/screens/bb7d6e68-6ec5-4bbf-abbc-b59e1389c10b): friendly illustration and concise benefits.

Artwork, brand colors, and the shaded illustration system are hybrd's existing assets.
