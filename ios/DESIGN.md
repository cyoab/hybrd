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

Plan is the home tab, followed by Progress and Coach. Profile is accessed through the avatar. The home screen shows the selected week, seven tappable days, actual-versus-planned totals, and the selected day's session cards. Calendar selection, horizontal week paging, full-week view, session opening, and moving use real local state.

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

The athlete profile keeps native Form, Picker, TextField, and Toggle semantics. Weekly running distance accepts direct, locale-aware numeric entry (3–150 km, including decimals); invalid or partial input blocks saving and review. Strength frequency uses a segmented picker and training days use accessible selected toggles. Profile saving is independent of plan creation; unsaved edits are protected. An optional starter-block review holds one immutable proposal, includes retained sessions, and only dismisses after successful acceptance; stale plan heads are rejected.

Session headers now use the Lifesum-inspired composition infographic described below. Run details retain a time-proportional prescribed sequence and an open vertical timeline; repeated work and recovery alternate in their true order. Strength details use numbered, expandable exercise rows with actual prescribed reps and RIR, rest guidance, and previous recorded sets when available. No illustration or prescription is presented as completed training.

All primary controls remain native and accessible. Headers wrap with Dynamic Type; session metrics stack at accessibility sizes; the day grid adapts to available width; illustrations are hidden from VoiceOver while the run diagram has a spoken chronological equivalent. Keyboard dismissal is available for name and distance fields. Simulator inspection remains unavailable in this Bitrig destination, so visual and assistive-technology behavior still need interactive verification.

## Lifesum-inspired session infographics

The session hero now uses a data-bearing composition graphic in place of the previous decorative track/barbell banner. References inspected in Mobbin:

- [Lifesum daily-progress widget](https://mobbin.com/screens/c832f3db-c966-43e7-b063-cc80e5d699aa): a central ring paired with compact, labeled breakdown bars.
- [Lifesum diary overview](https://mobbin.com/screens/668b7896-8d50-4a07-abaa-83de54f1f850): a prominent total, supporting metrics, and softer background treatment.
- [Lifesum food macro breakdown](https://mobbin.com/screens/2978a113-5407-42aa-9c1d-3303f5036312): directly labeled proportions and quantities.

The decision is one shared infographic pattern for both disciplines. Run arcs represent prescribed seconds by heart-rate zone, including an explicit unassigned category when HR targets are absent. Strength arcs represent actual prescribed set counts for each named exercise. Tapping a breakdown highlights its arc, shows its exact amount, and reveals prescription details; tapping it again restores the whole session. The chart is labeled as planned composition, never completion, readiness, muscle load, or recorded activity.

Terra anchors the expanded session palette alongside sky, mint, gold, and lavender. Each zone has a consistent color, a visible numbered label, and a matching tinted tile. New starter prescriptions carry explicit phase and HR-zone metadata; historical snapshots remain unchanged. Seconds remain visible for non-whole-minute intervals. Empty prescriptions show an explicit unavailable state. The chronological run strip uses the same colors and time proportions as the summary.

Native Swift Charts renders the sectors. Native buttons provide 44-point or larger hit targets and VoiceOver labels with amounts, percentages, and selection state. At accessibility text sizes the chart grows and the breakdown becomes a vertical list. Reduced Motion disables selection animation. Supporting metrics reflow when a compact width cannot fit the horizontal layout.

Validation: iPhone and Watch builds succeeded, and executable checks passed for phase totals, time shares, unequal exercise set counts, exact seconds, empty data, and unclassified legacy prescriptions. Offscreen SwiftUI renders were reviewed in light and dark appearance and with the accessibility layout. These renders used a temporary macOS harness with equivalent adaptive colors; they do not replace iPhone interaction, VoiceOver, or Dynamic Type verification in the simulator.

## Heart-rate targets and the Lifesum home direction

The leading reference is [Lifesum’s home diary](https://mobbin.com/screens/668b7896-8d50-4a07-abaa-83de54f1f850), with its broad gradient, centered ring, flanking metrics, and compact nutrient tiles. The session screen applies that structure with warm Terra/peach run backgrounds and lavender/blue strength backgrounds. Original, generated transparent shoe and dumbbell illustrations are bundled unmodified in `SessionShoe` and `SessionDumbbell` asset sets. No Lifesum artwork is bundled.

Run prescriptions display typed `HeartRateZone` targets in Plan, session details, the manual run log, and the Watch companion. The ring totals planned seconds by zone; interval badges and the chronological strip use the same colors. Zone 1 is sky, Zone 2 mint, Zone 3 gold, Zone 4 Terra, and Zone 5 lavender. The primary run metric is explicitly labeled as the work target when intervals exist. Tapping a zone reveals the contributing intervals. Actual post-session perceived effort remains a separate “How it felt” measure; it is never converted into heart-rate data.

The built-in starter recipe explicitly assigns Z2 to warm-up/easy running and Z1 to cooldown; the sample threshold recipe adds Z4 work and Z1 recovery. These are recipe targets, not a conversion of prior RPE numbers. Athletes can now enter their own four increasing BPM boundaries in the profile; these appear alongside zone targets in iPhone run details. Maximum-heart-rate estimates, HealthKit zone import, and live HR measurement are not implemented. [Apple’s zone guide](https://support.apple.com/en-mt/guide/watch/apd897dccddf/watchos) explains that personal zones can be calculated from health data or edited manually. [Polar’s five-zone description](https://support.polar.com/e_manuals/polar-loop/polar-loop-user-manual-english/heart-rate-zones.htm) informed the relative intensity labels; no vendor-specific BPM or percentage boundaries are assumed.

On load, known built-in future run recipes without zones are reissued in a new immutable plan version. Completed sessions, active drafts, past sessions, unknown recipes, and previous snapshots retain their exact prescriptions. The upgrade is idempotent and does not infer targets from an RPE string. Optional zone fields preserve older Codable data.

Validation includes iPhone/Watch builds; zone totals and round trips; legacy decoding; safe, idempotent plan upgrades; unknown/past/protected prescription preservation; and offscreen SwiftUI review of light, dark, compact, and accessibility layouts. Offscreen images use a temporary macOS harness and do not establish interactive iPhone/VoiceOver correctness. The existing Bitrig simulator-inspection limitation remains.

## Home refresh and swipeable weeks

The Plan home carries the session screens’ Lifesum-inspired color treatment into two compact actual-versus-planned tiles and illustrated session cards. Running uses Terra and peach; strength uses lavender; recovery uses mint. The existing original shoe/dumbbell artwork is reused. The main card keeps its HR-zone target and Open/Continue and Move actions, while the detailed interval list lives on the session screen.

The seven-day calendar remains prominent. A native horizontal scroll view snaps to complete weeks, replacing the two week arrows. Swiping retains the selected weekday and updates the date range, week number, totals, and sessions together. The date picker and Back to today remain available. A date-based window extends as the athlete approaches either edge; distant date-picker jumps reset a small window rather than allocating every intervening week. Calendar arithmetic handles daylight-saving and year boundaries.

Weekly rings use logged running distance and logged strength-session counts, matched by logical workout identity within the selected week. Partial lifts count as logged; skipped sessions and drafts do not. Ring fills cap at 100 percent, while the actual numbers remain uncapped. Sample prescriptions do not fabricate activity. Empty weeks show zero totals and a recovery state.

The selected day reverses contrast in dark appearance. At accessibility text sizes, the week becomes two rows within each page, progress tiles stack, artwork makes room for text, and session actions stack. Dates retain native button semantics, workout descriptions, selected traits, and named previous/next week accessibility actions; the graphical picker remains a direct-navigation alternative.

Validation: iPhone and Watch builds, core regression checks, and new calendar/weekly-total checks passed. Offscreen macOS SwiftUI/hosting renders covered light, dark, compact, and accessibility layouts; native lazy calendar pages were also mounted offscreen. Simulator inspection remains unavailable, so live iPhone swipe gestures, VoiceOver behavior, and exact iOS font scaling still need interactive verification.


## Athlete foundation, muscle focus, and gym setup

The profile is a native navigation hub with a soft lavender/Terra identity header. Personal information, experience, zones, benchmarks, strength preferences, training rhythm, and connections have distinct destinations. Unspecified body measurements, experience, zones, and records stay empty. Birthday entry is explicitly confirmed before adding age; no default demographic data is saved. Numeric fields retain invalid drafts and explain how to correct them. Profile saves compare the original profile against current storage and do not modify existing prescriptions, actuals, or drafts.

References inspected through Mobbin for this expansion:

- [Tempo muscle diagram](https://mobbin.com/screens/6f2e3b6a-889d-42ea-81cb-7cbcfda545a1): front/back anatomy and restrained selected-muscle emphasis.
- [Peloton Strength+](https://mobbin.com/screens/fc404a31-09fb-4061-bc52-8fd0096cea8f): clear muscle selection and training hierarchy.
- [Strava muscle visualization](https://mobbin.com/screens/74c48699-f4b2-41e5-bfe0-9b2d65bc2380): readable highlighted regions.
- [Future Pro equipment selection](https://mobbin.com/screens/4d08977f-bcee-4881-a6b1-6df84287ebb9): recognizable equipment cards and explicit selection states.
- [Peloton equipment chooser](https://mobbin.com/screens/222b1212-1f9e-4ccf-a4c1-351e9dd47144): concise grouped inventory.

Muscle illustrations are original SwiftUI vector paths. Front/back maps summarize the selection, and ten native Toggle cards pair individual muscle illustrations with names and checkmarks. Equipment uses twenty named, searchable Toggle cards grouped by type, plus an explicit bodyweight setup. Color is reinforced by text and selection marks; grids become single-column at accessibility sizes. An unconfigured gym remains distinct from an intentionally empty equipment inventory.

The bundled Free Exercise DB provides 876 internal reference records. The profile no longer exposes a library browser, category filters, or movement-reference pages. Strength PR entry uses a dedicated Choose lift picker with common lifts and matching search results. Its primary-equipment category is not a complete equipment requirement. New starter plans use a separate reviewed recipe set with explicit requirements and bodyweight alternatives. Muscle focus prioritizes movements within upper/lower sessions; it does not claim measured muscle load or a complete personalized program. User equipment and focus choices take effect only in an explicitly accepted new starter block.

Running PRs retain exact entered times. Strength PRs retain load and reps, with manual/logged provenance; no estimated one-rep maximum is substituted. Logged candidates exclude unfinished sets and skipped sessions and need explicit addition. Optional athlete details keep older stored profiles and plan snapshots decodable.

Health import requests only birth date, height, and weight after an explicit tap. The review shows available values and measurement dates; existing entries are unselected by default. Applying values edits the local draft, and Save profile persists it. There is no permission-success inference from absent Health data, automatic overwrite, background import, or current Strava connection. See `PROFILE-INTEGRATIONS.md` for setup and the deferred Strava contract.

Validation: Bitrig builds for iPhone and embedded Watch succeeded. Core checks and an isolated check of the actual SwiftData save path passed. Offscreen macOS SwiftUI renders covered the overview, personal information, muscle selector, equipment selector, and HR editor in light, dark, compact, and accessibility layouts. This does not establish interactive iPhone, VoiceOver, real Health authorization, or paired Watch delivery correctness. Bitrig simulator inspection remains unavailable, and no Apple account is currently connected for device provisioning.


## Illustrated gym inventory

All twenty gym equipment choices now have original shaded SwiftUI Canvas illustrations. Free weights use Terra, benches and stations use sky, machines use lavender, and accessories use mint. Distinct silhouettes, padding, grips, plates, and cable details help identify each item. Vector drawing keeps the artwork sharp across display scales without adding image downloads or bitmap assets.

The equipment artwork sits above the label inside each native Toggle card. A separate checkmark and selected border communicate state; the whole card remains tappable. Illustrations are decorative for VoiceOver, with the equipment name and native toggle state supplying the accessible meaning. Cards reflow at narrow widths and accessibility text sizes. Search, equipment persistence, and bodyweight selection retain their existing behavior.

Validation: the Bitrig iPhone/Watch build passed. Offscreen SwiftUI review covered all twenty illustrations in light and dark appearance and the gym screen at standard, compact, and accessibility layouts. These macOS renders do not replace interactive iPhone verification.


## Profile detail design system

About you, Experience, Heart-rate zones, and running/strength PRs share an illustrated header with rounded typography, pastel gradients, and original vector artwork. Identity uses an athlete card and ruler; experience pairs running and lifting; heart-rate editing uses a heart/pulse illustration; running uses a stopwatch and medal; strength uses a trophy with a barbell motif. The artwork is decorative and never represents recorded achievements or health measurements.

Measurement fields use prominent editable values with persistent labels and units. Running and strength experience stay independent native Pickers in Terra and lavender cards. Each HR zone has its numbered label and established zone color; Zones 2–5 expose direct integer BPM entry while Zone 1 follows the lower boundary. Valid personal ranges appear next to their zones, and invalid drafts retain corrective messaging. Running PRs use warm time-entry cards; strength PRs pair clear load/rep metrics with edit/delete controls and reviewed logged-set imports.

The standalone exercise-library navigation and browser have been removed. Catalog data remains behind the scenes, supplying a scoped movement choice only when adding or editing a strength PR. Existing records and catalog identifiers are preserved; no backend migration or network integration is implied.

Native Form/List containers, text fields, menu Pickers, sheets, swipe deletion, and keyboard controls retain their semantics. Headers stack at accessibility sizes, fields keep accessible labels, and illustrations are hidden from VoiceOver. Optional values, draft validation, explicit profile saving, and separate starter-plan acceptance remain intact.

Validation: Bitrig builds and core regression checks passed. Temporary offscreen macOS SwiftUI renders cover all five destinations plus the strength editor, lift picker, empty strength records, and invalid input in light, dark, compact, and accessibility layouts. Interactive iPhone and VoiceOver verification remain unavailable in this Bitrig destination.


## Goals and weekly rhythm

Goals & rhythm now uses the shared profile header and tinted form cards. Original calendar-and-clock vector artwork introduces the screen. Running, strength, and training focus use the established Terra, lavender, and mint palette with illustrated native menu Pickers. Weekly running volume keeps direct, locale-aware entry in a prominent measurement card; strength frequency keeps its native segmented control, and session duration remains a menu Picker.

Available weekdays are native Toggle cards on a mint surface. Checkmarks and contrasting fills distinguish selected days in both appearances. The grid reflows at narrow widths and accessibility sizes, and invalid distance or insufficient availability stays visibly explained. No goal, schedule, saved-profile, or starter-plan rules changed; these remain profile draft edits until the existing save/review flow is completed.

Validation: the Bitrig iPhone/Watch build and existing profile/planning checks passed. Offscreen macOS SwiftUI review covered light, dark, compact, and accessibility layouts, including a 72.5 km week and invalid distance/availability. Interactive iPhone verification remains unavailable in the current Bitrig destination.


## Appearance preference

The final section in Athlete profile offers Light, Dark, and System in a native segmented Picker, represented by sun, moon, and half-filled-circle SF Symbols. Each icon retains its spoken option name for accessibility. The compact icon control stays segmented at larger text sizes. System is the default; it requests no color-scheme override. The existing semantic colors, illustration palettes, wordmark, and native controls supply both appearances.

The choice is stored locally with AppStorage and takes effect immediately, independently of unsaved athlete edits and Save profile. The app root and profile sheet observe the same typed preference so the selection applies across tabs and presentations. This display preference is not part of training data or Watch synchronization.

Validation: Bitrig iPhone/Watch builds passed. An isolated offscreen macOS harness checked live Light/Dark changes at the actual ContentView root, storage restoration, fallback for unknown stored values, and compact/accessibility layouts. System saves successfully and maps to SwiftUI’s nil preference. The macOS harness retained its simulated application appearance when that override was cleared, so returning to and following System still needs interactive iPhone verification; simulator inspection remains unavailable.


## Run categories and running workouts

Runna references inspected through Mobbin: [workout chooser](https://mobbin.com/screens/dee5209e-fe41-49c9-9790-5611481f095f), [easy session](https://mobbin.com/screens/f57155bd-1060-49ac-8a9f-fcca371446d3), [progressive tempo session](https://mobbin.com/screens/89c9fece-8d56-4de3-83d3-fa3c1d848948), and [plan summary](https://mobbin.com/screens/90cc03b4-b6f7-467b-8dfc-4886cd4e4c3c). The design adopts consistent category colors, named choices, and an inspect-before-select flow. [Runna’s workout structure guide](https://support.runna.com/en/articles/15690947-understand-your-runna-workouts) informed the warm-up, main block, recoveries, and cool-down hierarchy. Workout copy and recipes are original; no Runna graphics, plans, personalized pace calculations, or recording behavior are copied.

Easy runs use lime, recovery blue, long runs lavender, tempo gold, intervals Terra, hills forest green, and progression teal. The same category follows home cards, calendar markers, and the session header in both appearances. Text and SF Symbols identify the type independently of color. Heart-rate charts retain the existing five-zone palette, which describes intensity rather than workout category. Optional run-type metadata decodes older snapshots; only known legacy recipe titles receive a presentation fallback. Unknown sessions remain generic runs.

Running workouts is available at the bottom of Plan. Eight time-based templates cover seven categories: Easy 30, Recovery 20, Long & easy, Tempo repeats, Steady tempo, Two-minute intervals, Hill repeats, and Build your rhythm. Cards visualize their actual prescribed sequence with duration-proportional bars and zone-proportional heights. Details reuse the zone ring and step-by-step prescription, show the selected date and existing sessions, and require Add to plan. Short-rep cues acknowledge HR response lag; hill recovery is a guide that can be extended. No distance, personal BPM boundaries, or performed results are fabricated. Weekly totals explicitly note time-based runs.

Adding a template creates a new plan version with new physical prescription IDs and retained logical workout identities. Older snapshots, logged results, in-progress drafts, and the athlete profile stay intact. Acceptance checks the reviewed plan head and rejects stale/repeated actions, invalid dates, and past dates. Starter generation still uses only easy and long easy runs; template browsing never silently adds harder training.

Validation: Bitrig iPhone/Watch builds and the core regression suite passed. New checks cover every recipe’s duration, alternating recoveries, HR targets/ranges, Codable compatibility, identifier renewal, unchanged historical snapshots, actual-result defaults, and weekly time-based counts. An isolated in-memory SwiftData harness exercised the actual TrainingStore save path, including stale heads, duplicate acceptance, invalid/past dates, and retention of results, drafts, and profile. Offscreen macOS SwiftUI renders covered the chooser, all run cards, progression preview, and home in light, dark, compact, and accessibility layouts. Interactive iPhone/VoiceOver verification remains unavailable in this Bitrig destination.


## Progress: a hybrid journey

Mobbin references inspected for this redesign:

- [Strava progress and best efforts](https://mobbin.com/screens/5189b97e-e26f-4946-b1b6-cafd7b6103f1): clear trends, discipline color, and best-effort recognition.
- [Gentler Streak comparisons](https://mobbin.com/screens/81ddb60b-a773-448c-b64a-92cef5221268): readable period totals and a calm activity history.
- [Apple Fitness summary](https://mobbin.com/screens/159f8961-41bd-4aa6-ad18-850ab81f4a52): at-a-glance accomplishment and distinct metric groupings.
- [Duolingo achievement collection](https://mobbin.com/screens/27423508-e523-49a9-a2bd-2c8eabe9e661) and [next achievement](https://mobbin.com/screens/cf300909-93e0-42c1-9612-5ef9e96d0dea): recognizable illustrated rewards, earned versus upcoming states, and a visible next target.
- [PlayStation trophies](https://mobbin.com/screens/db76eff0-901e-4dba-8a14-ded80c5e39f3): a persistent level and collectible achievement history.
- [Riot match recap](https://mobbin.com/screens/b4116f8d-3f99-42c1-a796-619c5652c061): personal results with a strong visual hierarchy.

The transferable game loop is visible accumulated work, recognition of an earned milestone, and a clear next step. Hybrd expresses it as a lifetime journey medal with one step per distinct logged training day and ten steps per level. Rest does not reset progress. No leaderboard, daily loss mechanic, random reward, escalating workout prescription, or invented fitness score is introduced. The level describes participation; the measured changes below it describe performance.

Original SwiftUI hexagonal medals, layered ribbons, sparkle details and rounded typography carry the illustration system into Progress. Terra identifies running; lavender identifies lifting; gold and mint distinguish participation and hybrid achievements. The hero uses a warm-to-lavender wash. Both appearances use semantic palette variants. Upcoming milestones and recent awards share the dashboard grid; the collection opens all eight and each medal explains its requirement and earned date. A short spring entrance in the detail sheet respects Reduce Motion; native selection feedback accompanies the period and milestone choices.

The 7-day, 4-week and 12-week selector persists locally. Totals compare with the preceding equal-length period; today's partial day is labeled. Separate running-distance and completed-set charts preserve units and allow date selection. Running comparisons require exact actual distance and run type; strength comparisons require the same exercise name and rep count. First, latest and best are visible with dates and explanatory context. A 28-day activity grid uses circle/square markers as well as color and opens the actual sessions for a selected day. Recent rows open their logged details, and history loads fifty rows at a time.

`ProgressSnapshot` derives all metrics from real results, excludes skipped/future/invalid activity, validates completed sets, deduplicates canonical IDs and repeated logical workout identities, and keeps lifetime awards independent of the selected period. Corrections can change achievements. The store caches by period, invalidates after actual/plan changes and local-day/timezone changes, and re-evaluates a pending future timestamp when it becomes eligible. The screen stays offline-first with an honest empty state and an entry into the athlete's next session. Profile PR entries without dated comparable histories do not become fabricated improvements.

The current native calendar uses logging dates, disclosed in the journey explanation. [Backend metrics handoff](../docs/progress-metrics-handoff.md) specifies the proposed compact summary and lazy comparison/activity endpoints, cache/projection strategy, versioned metric rules, and required migration to canonical performed dates and exercise identities. No backend endpoint was added by this UI change.

Validation: Bitrig iPhone/Watch builds and the core regression suite passed. Progress tests cover eligibility, partial/bodyweight sets, corrections, duplicate IDs, journey/milestone thresholds, recovery gaps, period boundaries, DST/year/midnight, exact effort matching, best values and stable comparisons. An isolated in-memory SwiftData harness exercised the actual TrainingStore finish/skip and cache paths, pending timestamps, calendar rollover and persistence. Offscreen macOS SwiftUI renders cover populated and empty dashboards, all medals, award details and history in light, dark, compact and accessibility-layout branches. These renders do not establish native iPhone interaction, actual iOS Dynamic Type sizing or VoiceOver correctness; interactive simulator inspection remains unavailable in this Bitrig destination.


## Live run and resistance workouts

Mobbin references: [Runna current interval and metrics](https://mobbin.com/screens/c98aeb61-c5de-4e25-8d3b-7449412f5c00), [Runna lap transition](https://mobbin.com/screens/49fbce7a-3366-4bb2-ad02-6f6b5dbc4b84), [Runna pause/resume](https://mobbin.com/screens/e81339ca-b595-42f0-86fe-01d4a7cb5728), and [Hevy actual set entry](https://mobbin.com/screens/a77f2375-2091-4762-b0f6-55de73e01a1b). The design adopts a clear current task, readable live values, stable controls, quick completion, and rest context. It uses hybrd's illustrations, category washes, rounded type and Terra/lavender palette, with original layouts and copy.

Running is Watch-first: the primary page makes elapsed time, pace, distance and fresh heart rate glanceable; a second page exposes current interval/HR target; the third contains recording controls. Native vertical paging and scrolling accommodate the small display. Display refresh slows when luminance is reduced. On iPhone, the live interval sits above a large pace readout and separate measured values. Finishing is confirmed, and the review includes route/laps rather than reverting to manual entry. Missing GPS/HR is explicit and personal BPM targets are never guessed.

Resistance now selects one exercise at a time, showing weight, reps and actual RIR with accessible native fields and a completion toggle. Last-time values stay beside their set. A completed set starts a lavender rest panel with countdown, extension/skip and optional locked-phone alerts. The next exercise remains an explicit action; completion of an unchecked set is never inferred from navigation. Accessibility sizes stack set labels and fields. Run/strength primary actions and all icon-only controls retain spoken labels.

See [workout recording implementation](WORKOUT-RECORDING.md) for data sources, local recovery, durable Watch delivery, native/backend mapping and verification limits. iPhone/Watch builds, model regressions and isolated persistence checks passed. Offscreen renders covered both appearances and compact/accessibility branches, including Watch-sized metric pages. Real GPS/HR, battery use, WatchConnectivity delivery, Apple Health permissions and native interaction still need physical-device verification.
