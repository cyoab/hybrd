# hybrd native design

## Source of truth

The brand is defined in `../docs/design.png`. The user-supplied home-screen mockup sets the layout direction. Mobbin references inform interaction patterns, while hybrd retains its own identity and concurrent-training model.

| Token | Value | Role |
| --- | --- | --- |
| Obsidian | #0D0D0E | Primary text, selected days, primary actions |
| Terra | #FF6B3D | Run markers, key sessions, brand dot, emphasis |
| Sand | #F4EDE7 | Warm neutral |
| Stone | #CBD5E1 | Inactive/completed markers, supporting structure |
| Mist | #F8FAFC | Main light background |

Small Terra text uses a darker accessible variant in light appearance. Dark appearance uses the same hierarchy with adapted surfaces and readable text. Run markers are circular; strength markers are square, so color is not the only signal.

## Navigation and home

Plan is the home tab, followed by Progress and Coach. Profile is accessed through the avatar. The home screen shows the selected week, seven tappable days, actual-versus-planned totals, and the selected day's session cards. Calendar selection, previous/next week, full-week view, session opening, and moving use real local state.

The sample block is explicitly labeled. Demo prescriptions never create actual results. Existing athlete results and drafts remain intact.

## References reviewed through Mobbin

- [Runna weekly plan overview](https://mobbin.com/screens/884d7416-da67-44b1-b8b0-1f5b1ce3fc0b): week navigation, concise workout summaries.
- [Runna run detail](https://mobbin.com/screens/243d2de3-9670-405b-be92-6d437c96526a): separate warm-up, repeat, and cooldown sections.
- [Runna structured run](https://mobbin.com/screens/64ccd319-791b-4f20-bb75-7340a44cd456): targets presented next to each step.
- [Hevy active workout](https://mobbin.com/screens/8bde1e5b-2e6a-4ff9-8079-40ac9b93d2b1): compact set/previous/kg/reps/completion table and exercise-local rest controls.
- [Hevy weight entry](https://mobbin.com/screens/fa1b4fe1-5d63-4e97-ac9a-ccdf41b86d7c): direct numeric entry while keeping the workout context visible.

Reference screenshots are not bundled into the app. The wordmark displays the original supplied artwork from an unmodified bundled brand sheet. SwiftUI clips to the wordmark region; dark appearance inverts and blends the artwork for contrast. The app icon is a vector rendering of the supplied h-and-dot mark, with a reproducible renderer in `Scripts/RenderBrandIcon.swift`.

## Workout interactions

Run details pair repeated work and recovery blocks and keep prescribed targets separate from actual run entry. The strength logger shows set number, actual previous results, kg, reps, and a check-off control. Added sets have no prescription ID; removing a prescribed set from the log produces a partial result rather than changing the prescription. The workout timer persists active time and excludes explicit pauses. Rest timing survives backgrounding, and draft results save locally after edits. Larger accessibility text uses a stacked set-row layout.

## Athlete profile and session redesign

Additional references inspected through Mobbin:

- [Duolingo athlete-style profile](https://mobbin.com/screens/4b289ec2-870f-445d-9a25-2e878cf4db25): distinctive identity header and clear hierarchy, without inventing achievements or progress for hybrd.
- [Revolut profile editing](https://mobbin.com/screens/7b3b7eec-703d-42b4-b16b-6743dc2400eb): simple labeled fields and separation of identity from account settings.
- [Headspace session detail](https://mobbin.com/screens/66694dd4-9baf-445f-9fb3-c17d68a49e42): an expressive illustration, editorial title, clear session metadata, and a persistent primary action.

The athlete profile keeps native Form, Picker, TextField, and Toggle semantics. Weekly running distance accepts direct, locale-aware numeric entry (3–150 km, including decimals); invalid or partial input blocks review. Strength frequency uses a segmented picker, training days use accessible selected toggles, and connections move into a dedicated native form. Unsaved edits are protected. The review holds one immutable proposal, includes retained sessions, and only dismisses after a successful save; stale plan heads are rejected.

Session headers use original SwiftUI vector track and barbell illustrations with adaptive brand colors. Metrics and purpose sit directly on the canvas. Run details include a time-proportional prescribed sequence and an open vertical timeline; repeated work and recovery alternate in their true order. Bar heights distinguish phases, not measured intensity. Strength details use numbered, expandable exercise rows with actual prescribed reps and RIR, rest guidance, and previous recorded sets when available. No illustration or prescription is presented as completed training.

All primary controls remain native and accessible. Headers wrap with Dynamic Type; session metrics stack at accessibility sizes; the day grid adapts to available width; illustrations are hidden from VoiceOver while the run diagram has a spoken chronological equivalent. Keyboard dismissal is available for name and distance fields. Simulator inspection remains unavailable in this Bitrig destination, so visual and assistive-technology behavior still need interactive verification.
