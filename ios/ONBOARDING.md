# Onboarding

**Create account** and **Sign in** now open the connected email flow. The manual journey saves to an account, resumes server drafts and completes real onboarding. Provider connections and paid membership are deferred for initial testing. See [BACKEND-INTEGRATION.md](BACKEND-INTEGRATION.md) and [BACKEND-ONBOARDING.md](BACKEND-ONBOARDING.md).

The signed-out welcome screen has only account creation and sign-in. It no longer offers anonymous exploration, onboarding preview or restart controls. A completed old preview cannot bypass authentication. The athlete profile also has no preview/test controls.

The following sections are retained as the historical onboarding/paywall design reference. Anonymous preview routes described below are no longer exposed in the app. The connected manual journey described in the integration guide is the only active route; billing remains deferred.
## Try it

- On the welcome screen, choose **Preview onboarding without an account**. **Explore the app** opens the existing app without completing setup.
- After entering the app, open **Athlete profile → Try sign-up & onboarding** to replay it.
- Close a question to return to the welcome screen; **Continue setup** resumes the saved step.
- **Start over** clears only the onboarding draft after confirmation. The live athlete profile, unit preferences, plans, workout recordings, and training history remain unchanged.
- **Restore purchases**, **Terms**, and **Privacy** explain the preview boundary. They do not pretend to authenticate, restore an entitlement, or accept a subscription agreement.

## Journey

1. Preferred name.
2. Running and strength goals, with an optional race date.
3. Balance between disciplines.
4. Running experience and recent weekly distance, including zero.
5. Lifting experience and current frequency.
6. Optional age, weight, and height in centimeters or feet/inches.
7. Available weekdays, desired lifting frequency, and session length.
8. Gym presets and an illustrated equipment selection.
9. Illustrated muscle priorities, or a balanced focus.
10. Readiness and an optional context note.
11. Preferences for connecting Health and Strava later; no permission prompts.
12. Personal recap with direct editing of every answer group. **Build my plan** starts a fixed four-second preview animation before membership selection; going back cancels it.
13. Annual/monthly membership selection, followed by a clearly identified preview completion.

Question progress indicates actual position. The requested four-second preparation animation reflects the selected goals, starting point, and rhythm, and is explicitly labeled as a preview; no account or plan is created. It respects Reduce Motion and cancels on dismissal. There are no invented performance promises. Answers can be edited from the recap and returned directly to it. Body details can be skipped.

## Preparation animation

The four-second transition uses one visual story instead of a loading ring and checklist:

- 0–1 seconds: the running shoe enters along a terra trail; the caption reflects the running goal.
- 1–2 seconds: the dumbbell joins on a violet trail; the caption reflects the strength goal.
- 2–3 seconds: both illustrations settle above a layered week card, and the athlete's selected weekdays appear in sequence.
- 3–4 seconds: the week settles, a mint seal and small sparkles appear, and a success haptic marks the final beat. The membership screen follows at the four-second deadline.

`OnboardingPreparationPhase` owns the four captions and personalized details. `OnboardingPlanArtwork` draws the illustration; its weekdays represent availability, not assigned workouts. `OnboardingPreparationView` owns the cancellable presentation task. Reduce Motion keeps the artwork settled and updates the caption and progress without travel, rotation, or spring effects. The preview disclosure remains visible.

Mobbin references: [Runna's finalizing screen](https://mobbin.com/screens/22bcb7e4-13aa-46e0-92eb-2eea43bcdf06) informed the single visual focus and short status line; [Speak's personalized setup](https://mobbin.com/screens/4f4cad1c-c29a-48d7-b3ac-6524ff40d44d) informed making the assembled content part of the illustration. These results expose screen references, not playable animation footage; the motion is an original SwiftUI sequence using hybrd assets.

The isolated layout fixture captured all four beats in light/dark appearance, at 320-point width, and with the reduced-motion path enabled. Completion callbacks occurred at approximately 4–4.3 seconds including initial host setup; dismissing mid-animation canceled the callback. Native iPhone interaction coverage remains subject to the simulator limitation below.

## Membership presentation

The user confirmed USD prices:

| Option | Total | Supporting comparison |
| --- | --- | --- |
| Monthly | US$10.99 each month | Flexible monthly commitment |
| Annual | US$99.99 each year | Approximately US$8.33/month; “Get 2 months free” compared with monthly billing |

The two-month message is a billing comparison, not a free trial: US$99.99 is lower than ten monthly payments at US$10.99.

Annual is initially selected. Total charge and billing interval remain prominent. The copy explicitly states that this is a preview, no charge occurs, and no free trial is included. Completing the screen saves only the selected offer and the local preview-completion flag. It does **not** grant a subscription entitlement.

## State and integration boundary

- `OnboardingDraft` contains typed goals, experience, preferences, optional body details, and selected membership.
- `OnboardingStore` owns navigation, validation, review mode, and versioned persistence under `hybrd.onboarding.preview.v1` in UserDefaults.
- The store never reads or writes `TrainingStore` or billing/authentication state. `AppEntryView` preserves access to an active or recovered run.
- Display units are independent of the live athlete settings. Height supports separate feet/inches fields and preserves centimeters as its physical value. Legacy drafts without a height preference decode as centimeters. Distance, height, and body-weight conversions retain exact canonical quantities while toggling; clearing a field invalidates the previous conversion baseline.
- An unreadable saved preview is preserved until an explicit restart. Restart also leaves unrelated UserDefaults values intact.
- Running baseline accepts 0–250 km/week. This describes the athlete's recent activity; it is not the existing local planner's 3–150 km prescription target. A future planner must handle zero and higher-volume baselines deliberately rather than clamping them silently.
- Copy is included in English, Spanish, Brazilian Portuguese, and French, including native plural handling.

Authenticated routing and idempotent manual onboarding are now available in the connected flow. Before production, complete the acceptance checks in the integration guide and the deferred consent/provider/billing work. Do not treat `completed` or `enteredApp` as authentication or entitlement signals. Plan creation must use reviewed canonical values and account for stated limitations. Integrate Health/Strava only after separate explicit consent and review of imported values.

Real memberships need App Store Connect products, StoreKit product-provided prices and billing periods, verified transactions/entitlements, pending/canceled/error handling, restore behavior, and final terms/privacy URLs. The hard-coded USD preview is not a production pricing source. Nothing in this change provisions products or starts payments.

## Validation

`bash ios/Scripts/check-core.sh` covers validation, zero/high mileage, repeated unit conversions, imperial height input/validation and legacy height drafts, cleared-input conversion, all step transitions, recap editing, persistence/resume, isolated restart, corrupt draft recovery, USD offer math, and four-language formatting. The existing workout, profile, progress, and localization regression checks also pass.

An isolated SwiftUI fixture also verified that the preparation callback occurs after approximately four seconds and that removing the preparation view cancels the callback. The timer is presentation-only; future real account/plan creation must use verified backend success, including error handling, rather than treating timer completion as success.

Bitrig builds pass for the configured iPhone/Watch project. The welcome screen was inspected in the native iPhone preview. Isolated SwiftUI layout fixtures were reviewed in light/dark appearance and at narrow widths; these supplement rather than replace iPhone interaction testing. The current Bitrig iPhone automation reports that simulator state is unsupported, and native automation taps fail with `noWindowsAvailable`, so a complete automated tap-through and native keyboard/VoiceOver/Dynamic Type checks remain unverified.

Suggested device review:

- Finish a new-user journey with zero mileage and skipped body details.
- Confirm steps 5 and 7 show permanent labels for current lifting frequency, desired frequency, and time per workout.
- Enter 70 km directly, toggle miles and back, clear the field, switch units, and enter another value.
- Enter 5 ft 10 in, switch to centimeters and back, then skip body details.
- Tap **Build my plan** on the recap; check the four-second transition and cancel/back behavior.
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
