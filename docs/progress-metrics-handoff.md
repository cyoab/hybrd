# Progress metrics: backend implementation handoff

Status: proposed API/read model, **not implemented server endpoints**. The iOS Progress tab already derives these metrics offline from locally persisted results using `ios/Shared/ProgressSnapshot.swift`. No server migration, credentials, or network dependency is introduced by this UI change.

## Product and data contract

The screen combines a lifetime journey, 7/28/84-day totals and comparison periods, a volume chart, matched-effort changes, a 28-day calendar, earned milestones, and browsable actuals. A new account must show empty totals and locked milestones, never sample achievements. Scheduled prescriptions, profile PRs without dated histories, unfinished sets, and draft workouts are not performed activity.

The existing canonical result aggregate in `server/src/workouts/schemas.ts` already has `trainingDate`, `timezone`, actual running data and completed strength sets. Normalized tables are in `server/src/db/schema/training.ts`. Actuals continue to be written through the existing revisioned sync protocol; the endpoints below are read-only projections.

## Recommended endpoints

| Endpoint | Purpose | Response |
| --- | --- | --- |
| `GET /v1/progress/summary?periodDays=28&timezone=America/Monterrey` | One bounded request for the initial screen | Period totals, lifetime totals, daily series, 28-day activity, journey, milestones, two comparison previews, three recent actuals |
| `GET /v1/progress/comparisons/{comparisonKey}?cursor=…&limit=50` | Lazy loading of a selected comparable effort's history | Measurement/date/source-result IDs, exact grouping rule, best/first/latest, opaque continuation cursor |
| `GET /v1/progress/activity?from=YYYY-MM-DD&to=YYYY-MM-DD&cursor=…&limit=50` | Date drill-down and paginated actual-result list | Compact titles, discipline/status, logged/performed dates, actual totals and canonical result ID/revision |

`periodDays` accepts only 7, 28, or 84. Validate IANA timezone, date bounds, cursor binding, and a maximum page size of 100. Derive athlete ownership from the existing authenticated session; never accept an arbitrary athlete ID as authorization. Return the standard error/request ID format. Detail can use the locally synchronized `workout_result` aggregate; no second write or sync route is required.

The server supplies `asOf` at calculation time. Do not accept a historical `asOf` parameter until true historical revision reconstruction is supported. The summary should contain:

- `schemaVersion`, `rulesVersion`, `asOf`, `timezone`, `dateBasis`, `dataRevision` and `projectionSequence` (revision/sequence values remain decimal strings).
- `range: {startDate,endDateInclusive,includesPartialToday:true,previousStartDate,previousEndDateInclusive}`. Dates are inclusive calendar dates, not multiples of 86,400 seconds.
- `totals: {current,previous,lifetime}`, each with actual run meters, completed strength sets, active seconds, sessions, run sessions, lift sessions and distinct active days. Missing comparison percentages are null when the previous value is zero.
- `series`: 7/28/84 zero-filled daily buckets in ascending order. The client groups consecutive seven-day buckets for longer charts; sums must equal current totals.
- `activityDays`: exactly the last 28 calendar days, independent of the selected period, with run/lift counts and actual totals.
- `journey: {trainingDays,level,stepsInLevel,stepsToNextLevel}`.
- `milestones`: stable key, requirement/target/current value/unit, `earnedAt`/`earnedOn` (nullable), evidence result ID, and rule version. Display text can remain localized in the app.
- `comparisons`: at most one running and one strength preview, containing a typed group key, first/latest/best measurements, sample count, representative chart points and source result IDs. Return exact extrema/first/latest independently of any chart downsampling. Indicate `hasMore`.
- `recentActivity`: at most three compact actual-result rows. Avoid full prescriptions, segment traces, every historical set, or every comparison sample in this payload.

Comparison keys must be opaque and ownership-checked. Use stable pagination ordered by `(trainingDate, resultID)` or another documented unique tuple, bound to the query and a projection revision; expire or restart cursors after conflicting edits rather than returning duplicates silently. A profile screen or achievement overlay should reuse the summary cache.

## Rule version 1

1. Use non-deleted canonical actuals. `skipped` never counts. Positive run distance and duration count; partial run work contributes volume but cannot supply a completed effort comparison. Strength counts completed sets with a named/canonical exercise, valid reps and nonnegative finite load. Zero-load bodyweight sets count. Failed, skipped and unfinished sets do not. Count all valid completed sets for v1; do not silently change to working sets only.
2. Deduplicate result IDs before aggregation. Preserve the canonical provider/external ID/fingerprint rules in `activity_source_records`; joining an import link must never duplicate an actual. A source-record deletion alone does not delete its workout. Native legacy duplicates for one logical workout select the latest logged result deterministically before eligibility filtering, so a latest skipped correction can revoke old work. Server v1 must define the same single effective result policy for repeated non-null logical workout IDs using canonical revision/order; unplanned null logical IDs stay distinct by result ID. Flag unresolved matches instead of silently summing or guessing.
3. One eligible calendar day earns one journey step, regardless of sessions or disciplines on it. `level = 1 + floor(distinctDays / 10)`, `stepsInLevel = distinctDays % 10`, `stepsToNextLevel = 10 - stepsInLevel`. This describes participation, not fitness. Rest days never remove steps; no consecutive-day streak or escalating load incentive.
4. Milestone keys/thresholds: `firstDay` 1 day; `bothDisciplines` a run and a lift on any days; `tenKilometers` 10,000 m; `twentyFiveSets` 25 sets; `tenDays` 10 days; `fiftyKilometers` 50,000 m; `hundredSets` 100 sets; `fiftyDays` 50 days. Earn on the first chronological qualifying crossing. Calculate from current records; corrections/deletions can move an earned date or revoke an award. A stable rule-version/milestone key prevents repeated celebration without blocking legitimate recalculation.
5. Run changes compare **completed sessions of exactly the same actual meter distance and known workout type**, minimum 1,000 m. Value is elapsed run seconds / actual km. Use whole-session elapsed duration consistently; do not mix moving and elapsed pace. No approximate-distance PR inference, extrapolated race times, or fitness prediction. Unknown type remains `custom`, visibly identified. The UI states that route, conditions and effort may differ.
6. Strength changes compare the same exercise and rep count. Use the heaviest valid completed set within each session. The server should key by canonical exercise ID, including explicit substitution identity; the current offline native model only has exact exercise name and must migrate before full parity. Compare first to latest across different training dates; best is independently minimum pace or maximum load. Do not estimate 1RM or mix exercise variants, rep counts, or assistance/load conventions.
7. Pick the most recently logged eligible comparison in each discipline, with deterministic group-key tie breaking. First/latest refer to the entire eligible history, not the selected volume period. Use at least two distinct dates; distinguish regression/holding steady from improvement without assigning failure language.
8. Treat `modified`/`abandoned` backend results explicitly: valid performed work may contribute totals, but only `completed` runs enter effort comparisons. Native currently represents completed/partial/skipped. Map statuses during sync without inventing completion. Retain provenance and explain excluded/invalid data.

## Date and identity migration needed on iOS

The native `WorkoutResult.completedAt` currently records **logging time**. The calendar groups it in the device timezone and the journey explanation discloses this. It does not pretend the scheduled date is when work happened. The backend already has canonical `trainingDate` plus the workout's IANA timezone.

Before switching the UI to remote totals, add native actual `trainingDate`/`timezone`, canonical result revision and canonical exercise ID, with backward-compatible decoding. New activity should capture performed dates explicitly. Legacy undated actuals retain `dateBasis:loggedDate` until the athlete confirms the performed date; never silently backdate them to a prescription. Do not fill unknown start/end instants from upload time. Preserve historical training dates when traveling; the query timezone determines today's range boundaries, while the stored local performed day remains authoritative. Return mixed/legacy date provenance when present. This date-policy change is a deliberate metric migration and needs parity fixtures and a rule version, not an invisible date shift.

Map existing server `planned_workouts.workoutType` strings to a documented enum compatible with native run types (easy, recovery, long, tempo, intervals, hills, progression, custom). Resolve against the exact historical physical planned-workout ID, not the currently active plan. Missing/unknown type stays custom. Titles can change; never classify arbitrary titles into workouts or canonical exercise IDs.

## Projection, cache and query plan

- Start with indexed reads and measured query plans; `results_owner_date_idx(athlete_id, training_date)` already exists. Reuse it. Add owner/date/result-ID or partial non-deleted variants only if plans demonstrate a benefit; index strength exercise/result joins and canonical exercise/rep lookup as appropriate.
- Preaggregate run and completed-set data per result before joining. Joining segments and sets directly can multiply rows and inflate accomplishments.
- For longer histories, maintain per-athlete/day rollups and a compact comparison projection. Emit projection work transactionally through an outbox when sync commits a workout aggregate update/delete, set replacement, logical-result resolution, or source matching. Recompute both old and new affected dates on moves. Changes can alter all-time first/best/latest, day counts and milestone crossings; simple increment-only counters are insufficient.
- Keep a source mutation sequence and projection sequence. Read a consistent projection snapshot for all summary components. If projection work lags, return `freshness:updating` plus both watermarks, or fall back to bounded canonical calculation; never claim partial rollups are current.
- Use a private authenticated cache. An ETag includes athlete scope, schema/rules version, timezone/date policy, period, local day, and data revision. Support `If-None-Match`/304 and midnight expiration. User account deletion must purge projections and private caches. Logout clears the native summary.
- The native app already caches snapshots per period and invalidates on result/plan changes, local midnight/timezone changes and pending result timestamps. Keep it responsive offline. During future sync integration, do not add all local totals to server totals: they overlap. Prefer the complete local projection after a full pull, or maintain a revisioned overlay for explicitly unacknowledged result mutations including replacement/deletion deltas. Until reconciliation is supported, keep one authoritative snapshot source per render and show its freshness.
- Proposed budgets, to validate with real data: cached p95 <200 ms, cold p95 <500 ms, initial compressed summary <=30 KB. Cap/downsample chart histories and paginate activity so 10,000 results does not create an unbounded response. Benchmark rather than treating these as achieved service guarantees.

## Acceptance checks

Test empty/one-result accounts; all period and previous-period boundaries; DST, leap/year edges and travel; partial today; future or malformed actuals; partial versus completed; bodyweight sets; extra/failed/skipped sets; same-day doubles; rest gaps; duplicate imports and repeated logical IDs; null unplanned IDs; aggregate set replacements; correction/deletion that revokes an award or former best; exact run distance/type and exercise/rep matching; deterministic ties; zero denominators; midnight invalidation; outbox replay and projection lag; pagination under concurrent edits; cross-athlete access denial; and account purge.

Compare endpoint fixtures against the native `Tests/ProgressChecks.swift` suite, adding canonical date/exercise identity migration fixtures before claiming parity. Register named response schemas in the existing Hono/Zod OpenAPI pipeline and regenerate `contracts/openapi.yaml`; do not hand-edit a divergent contract.
