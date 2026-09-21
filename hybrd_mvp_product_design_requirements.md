# hybrd

## MVP Product Design Requirements

**Concurrent Training Operating System**

What the MVP must accomplish — independent of implementation, architecture, frameworks, vendors, or technical tooling.

| **Document** | MVP Product Design Requirements |
|--------------|---------------------------------|
| **Product**  | hybrd                           |
| **Version**  | 0.1                             |
| **Date**     | 21 September 2026               |

> **North-star product statement**
>
> hybrd is the training operating system for athletes who want to improve endurance and strength at the same time. The MVP must treat running and lifting as one coordinated training problem rather than two unrelated workout logs.

Audience: product, design, engineering, and specialized implementation agents. This document defines desired product behavior and outcomes only.

# Contents

**1** Product definition

**2** MVP goals and non-goals

**3** Core product principles

**4** Primary user and canonical use cases

**5** MVP feature requirements

**6** Cross-feature product behavior

**7** Data and user-control requirements

**8** Success criteria

**9** Explicitly out of scope for MVP

**10** MVP+ differentiators and roadmap boundary

**11** Open product decisions for implementation planning

# 1. Product definition

hybrd is a performance-training application for athletes who intentionally combine running and resistance training and want both disciplines to improve within a single, coordinated plan.

The MVP is not simply a running app with a strength tab, nor a lifting logger with cardio attached. Its defining responsibility is to understand the athlete’s goals, planned training, completed training, and recent response across both disciplines, then keep those elements coherent over time.

### Core problem

Serious hybrid athletes currently distribute their training across multiple products. One system may prescribe runs, another logs lifting, another stores wearable data, and another is used for notes or analysis. Each product can be excellent inside its own domain while remaining unaware of the total training stress imposed on the athlete.

> **The job to be done**
>
> Help me plan, execute, understand, and adapt my running and lifting as one training system so that progress in one discipline does not needlessly undermine progress in the other.

### MVP promise

- **Plan together.** Running and strength sessions are created and scheduled as parts of one program.

- **Track properly.** Each discipline gets a purpose-built workout experience rather than a generic “activity” form.

- **Understand together.** Progress and training stress can be viewed by discipline and as a combined picture.

- **Adapt together.** When training changes, future sessions can change coherently instead of becoming stale.

- **Explain decisions.** The athlete can understand why the plan looks the way it does and why it changes.

# 2. MVP goals and non-goals

### Goals

- Allow a new athlete to describe concurrent endurance and strength goals in enough detail to produce meaningful training.

- Create a unified, editable training calendar containing both running and strength sessions.

- Make logging a strength session fast enough for regular gym use and detailed enough to measure progression.

- Represent and log structured running workouts accurately enough for serious recreational runners.

- Ingest completed training from external fitness sources so the athlete does not need to duplicate all activity entry.

- Import enough historical training to establish a useful starting context for analysis and planning.

- Generate a coherent hybrid training plan that respects the athlete’s priorities, availability, current training, and likely interference between sessions.

- Use completed performance to update future prescriptions instead of treating the initial plan as fixed.

- Give the athlete a concise view of whether running, lifting, and the combined program are moving in the intended direction.

- Provide an AI coach capable of answering athlete-specific questions using the athlete’s actual plan, history, performance, and goals.

- Allow the athlete to reschedule or miss training without manually repairing the entire week.

### Non-goals

- Be a social network or activity feed.

- Replace a wearable or become the primary physiological sensor.

- Offer comprehensive nutrition, calorie, or meal tracking.

- Provide medical diagnosis, injury diagnosis, or treatment recommendations.

- Serve every sport at launch. The core MVP disciplines are running and resistance training.

- Reproduce every advanced metric found in specialist endurance-analysis platforms.

- Operate as a marketplace for coaches, races, equipment, or training plans.

- Guarantee performance outcomes. The product supports training decisions; it does not promise a specific race time, strength number, or health outcome.

# 3. Core product principles

> **Concurrent by default**
>
> Any planning or adaptation decision should consider both running and lifting unless the athlete has explicitly chosen to isolate one discipline.

> **Specific where specificity matters**
>
> Running and strength require different workout models, logging interactions, progression signals, and performance metrics. The product should not flatten them into one generic activity schema from the user’s point of view.

> **Athlete priorities are explicit**
>
> The product must know which goals matter most and what the athlete is willing to maintain, sacrifice, or defer.

> **The calendar is the shared truth**
>
> Planned work, completed work, moved sessions, missed sessions, and future adaptations should converge in one understandable schedule.

> **Recommendations are inspectable**
>
> When hybrd changes or recommends training, the athlete should be able to understand the reason in plain language.

> **Automation remains controllable**
>
> The system may suggest and apply changes, but the athlete retains visibility and control over material plan changes.

> **Progress beats metric abundance**
>
> The MVP should emphasize measurements that change training decisions rather than maximizing the number of charts.

> **Historical context matters**
>
> The application should use prior training whenever available rather than treating every new account as an untrained blank slate.

# 4. Primary user and canonical use cases

### Primary MVP user

A committed recreational or competitive athlete who trains multiple times per week, intentionally pursues both running and strength outcomes, already tracks at least some workouts, and cares about measurable progression. This user is willing to follow structured training and wants more guidance than a simple workout log provides.

### Representative goals

- Prepare for a 5K, 10K, half marathon, or marathon while maintaining or improving major lifts.

- Prioritize hypertrophy or strength while retaining meaningful running fitness.

- Improve general hybrid performance without a near-term race.

- Maintain strength during a high-volume endurance block.

- Build running volume without allowing lower-body strength work to repeatedly compromise key sessions.

### Canonical use cases

| **Field**           | **Requirement**                                                                                                                                                   |
|---------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Plan a block**    | The athlete defines goals, availability, experience, and current training. hybrd produces a coordinated multi-week plan with running and lifting.                 |
| **Execute today**   | The athlete opens today’s planned session, sees exactly what is expected, completes it, and records relevant results with minimal friction.                       |
| **Import a run**    | A run recorded elsewhere appears in hybrd, is matched to the intended session when appropriate, and contributes to history and progress.                          |
| **Miss training**   | The athlete skips or cannot perform a session. The plan acknowledges the miss and helps preserve the week without blindly stacking displaced work.                |
| **Move training**   | The athlete moves a session. The product identifies material conflicts with adjacent sessions and helps keep the schedule coherent.                               |
| **Ask the coach**   | The athlete asks a question about recent performance or the plan and receives an answer grounded in their own training data.                                      |
| **Review progress** | The athlete can tell whether running fitness, strength performance, adherence, and total training are improving or deteriorating over an appropriate time window. |

# 5. MVP feature requirements

The following features define the P0 launch scope. Each section describes the required outcome, user behavior, product rules, and acceptance criteria. Implementation mechanisms are intentionally unspecified.

**01 Athlete profile and dual-goal definition**

*Create a persistent model of what the athlete is training for, what matters most, and what constraints the plan must respect.*

### Purpose

The profile gives the rest of hybrd enough context to make coherent decisions. It must capture both endurance and strength objectives rather than forcing the athlete into a single primary sport identity.

### The athlete must be able to define

- **Endurance objective.** General fitness or a running objective such as 5K, 10K, half marathon, or marathon; race date when applicable; optional target performance.

- **Strength objective.** Strength, hypertrophy, maintenance, or a combination; optional target lifts or body-part priorities.

- **Relative priority.** Which discipline currently has priority and approximately how strongly. The athlete may select balanced training or bias the plan toward running or strength.

- **Training availability.** Days available, preferred days, days unavailable, approximate session windows or duration constraints where relevant.

- **Current training baseline.** Recent running frequency and volume, longest recent run, strength frequency, representative recent strength performance, and training experience.

- **Preferences and constraints.** Preferred training days, preferred or excluded movements, available training environment/equipment at a product level, and practical scheduling constraints.

- **Subjective context.** Optional information such as current perceived fatigue or recent interruption that materially changes the starting point.

### Product rules

- The athlete can change goals and priorities later without creating a new account.

- A material goal change must be treated as a change to future training intent, not silently rewritten into past history.

- The product should distinguish required information from optional information and allow a reasonable setup path without demanding perfect historical data.

- If imported history is available, the product may use it to reduce repetitive setup questions, but the athlete must be able to correct the resulting profile.

### Acceptance criteria

**✓** A new athlete can complete setup with one endurance objective, one strength objective, relative priority, availability, and baseline training information.

**✓** The profile supports a runner-first, strength-first, and balanced athlete without changing products or modes.

**✓** Changing priority or target dates updates the future planning context while preserving completed history.

**✓** The athlete can inspect and edit the current profile at any time.

**02 Unified training calendar**

*Provide one authoritative schedule for planned and completed running and strength training.*

### Purpose

The calendar is where concurrent training becomes visible. It must let the athlete understand not only what they are doing today, but how running and lifting are distributed across the week and how moving one session may affect another.

### Required capabilities

- Week and day views that show running and strength sessions together.

- Clear visual distinction between planned, completed, modified, missed, and optional sessions.

- Ability to open any session and inspect its purpose and prescription.

- Ability to move a future session to another date.

- Ability to mark a session as skipped, unavailable, or intentionally removed.

- Ability to add an unplanned run or strength session.

- Ability to see planned versus completed work for the week.

- Ability to identify sessions designated as key/quality work versus supporting/easy work.

- Ability to view a multi-week block so the athlete can understand progression and deload/taper structure where relevant.

### Concurrent-training behavior

- The calendar must recognize when a moved or newly added session creates a meaningful proximity/conflict with another key session.

- Conflicts should be expressed in athlete-readable terms such as lower-body fatigue before a key run, clustered high-intensity work, or excessive session density.

- The product should not block the athlete from making a change solely because it is suboptimal. It should explain the concern and allow an informed choice.

- When an applied schedule change materially affects future training, the athlete should be offered an updated plan rather than left with an internally inconsistent week.

### Acceptance criteria

**✓** An athlete can understand the entire week’s running and lifting schedule from one view.

**✓** Moving a key strength or running session causes relevant nearby conflicts to be surfaced before or immediately after the move.

**✓** Missed and completed sessions remain distinguishable from originally planned sessions.

**✓** Planned weekly running volume and strength-session count can be compared with actual completion.

**03 Strength workout prescription and logger**

*Make strength training precise, fast to execute, and measurable enough to drive progressive overload and future plan changes.*

### Workout prescription

- Each strength session has a clear purpose and ordered list of exercises.

- Each exercise can prescribe sets, rep targets or ranges, load guidance where available, effort target using RPE and/or RIR, rest guidance, and optional coaching notes.

- Exercises may be grouped into supersets or other simple paired structures.

- Warm-up work can be distinguished from working sets.

- An exercise may include an approved substitution or allow the athlete to choose a substitution while preserving the intended training target.

### Logging experience

- Record actual reps and load for every set.

- Record actual effort using RPE/RIR when desired or requested by the workout.

- Mark warm-up, working, failure, or other meaningful set status supported by the prescription.

- Add session-level and exercise-level notes.

- See recent performance for the same exercise while logging, including the previous comparable session where possible.

- Use a rest timer without leaving the workout flow.

- Complete, pause, resume, or intentionally end a workout early.

- Add, remove, reorder, or substitute exercises when real-world conditions require it.

### Performance outputs

- Exercise history over time.

- Personal records and best performances for relevant rep/load combinations.

- Estimated strength trend such as estimated one-repetition maximum where enough information exists.

- Training volume and hard-set counts at session and relevant muscle-group levels.

- Planned versus actual set/rep/load/effort comparison.

### Product rules

- Logging must preserve what was prescribed and what actually happened as separate concepts.

- Exercise substitutions should maintain a record of both the original intent and the performed movement.

- Incomplete sessions must still contribute the work actually performed rather than being discarded.

- The product must not require the athlete to test true maximal lifts to estimate progress.

### Acceptance criteria

**✓** An athlete can complete a typical strength workout without repeatedly navigating away from the active session.

**✓** The logger stores actual set-by-set performance and preserves the original prescription for comparison.

**✓** Recent comparable exercise performance is visible during logging.

**✓** Completed strength data contributes to progression, analytics, and coaching context.

**04 Structured running workout model and execution record**

*Represent serious running sessions accurately enough to prescribe, evaluate, and compare training over time.*

### Supported workout structure

- Easy/recovery runs.

- Long runs.

- Progression runs.

- Tempo/threshold sessions.

- Interval and repetition sessions.

- Runs containing warm-up, work segments, recoveries, and cooldown.

- Optional strides or short accelerations within a session.

### Prescription dimensions

- Distance and/or duration.

- Pace target or range when appropriate.

- Heart-rate target or range when appropriate.

- RPE/effort target when appropriate.

- Recovery duration/distance between work segments.

- Purpose and plain-language instructions.

### Completed-run record

- Total distance and duration.

- Average and segmented pace.

- Heart rate when available, including useful time-in-zone summaries.

- Elevation where available.

- Cadence and other common running metrics when available, without making them mandatory.

- Splits or segment performance sufficient to evaluate whether the intended workout was executed.

- Athlete-reported RPE and optional notes.

- Whether the workout was completed, partially completed, modified, or abandoned.

### Evaluation behavior

The product should be able to compare the completed run with the prescription at the level necessary to answer questions such as: Was the planned distance completed? Were the work segments near target? Was effort materially higher or lower than intended? Did the athlete modify the session?

### Acceptance criteria

**✓** A structured interval or tempo workout can be represented without reducing it to a single distance and pace target.

**✓** Imported or manually recorded runs can retain enough segment information to evaluate planned versus actual work when the source provides it.

**✓** The athlete can add RPE and notes even when objective data was imported automatically.

**✓** Completed running data contributes to progression, analytics, and coaching context.

**05 External activity ingestion**

*Bring completed training into hybrd so the athlete does not need to manually reproduce workouts recorded elsewhere.*

### Purpose

hybrd should operate as a coherent training record even when activities are captured by a watch, phone, or another fitness service. External ingestion is therefore part of the product experience, not an optional export utility.

### Required behavior

- The athlete can connect at least one supported external activity source during or after onboarding.

- New supported running activities can appear in hybrd without the athlete manually recreating the run.

- Where sufficient evidence exists, an imported activity can be matched to the planned session it represents.

- The athlete can confirm or correct an uncertain match.

- Imported activities preserve their original activity date/time and core metrics.

- Duplicate imports of the same underlying workout should be prevented or clearly reconcilable.

- If an activity is edited or deleted at the source and the source communicates that change, hybrd should avoid silently presenting contradictory duplicates.

### Source independence

The MVP requirement is the behavior above, not a specific provider. The product should conceptually support multiple sources over time without changing the athlete-facing meaning of a run, completed workout, or historical record.

### Failure and ambiguity states

- Connection unavailable or expired.

- Activity imported with incomplete metrics.

- Activity could match more than one planned session.

- Unexpected activity not present on the plan.

- Duplicate activity detected.

- Activity type unsupported by the MVP.

### Acceptance criteria

**✓** An athlete who records a supported run externally can see that completed run reflected in hybrd.

**✓** The athlete can tell whether an imported activity has been matched to a planned workout.

**✓** Uncertain matching is never silently treated as certain.

**✓** Imported data does not require all possible metrics in order to be useful.

**06 Historical training import and baseline reconstruction**

*Start with the athlete’s real recent training context instead of requiring weeks of new data before becoming useful.*

### Purpose

A new hybrd account should be able to become context-aware quickly. When historical data is available, the product should reconstruct a reasonable recent training picture that can inform initial planning and analysis.

### Required outcomes

- Import a meaningful recent window of historical supported activities.

- Calculate recent running frequency, weekly volume, long-run history, intensity distribution where possible, and relevant performance trends.

- Incorporate imported strength history when available in a form the product can understand; otherwise permit the athlete to provide representative recent strength performance manually.

- Identify obvious gaps or low-confidence parts of the historical record.

- Allow the athlete to correct an implausible baseline before it affects the plan.

### Product rules

- Absence of history must not prevent onboarding.

- History should inform the starting workload but should not automatically be interpreted as optimal training.

- Historical estimates should distinguish observed facts from inferred values.

- A single outlier week should not dominate the baseline when a broader recent pattern is available.

### Acceptance criteria

**✓** An athlete with available historical running data can receive a starting plan that reflects recent training volume rather than default beginner assumptions.

**✓** The athlete can see the recent baseline hybrd inferred and correct it before finalizing the plan.

**✓** Missing strength history can be replaced with a lightweight manual baseline rather than blocking plan creation.

**07 Hybrid plan generator and interference-aware scheduling**

*Create one coordinated running + strength program whose structure reflects priorities, recovery needs, and interactions between sessions.*

### Purpose

This is the defining MVP feature. The plan generator must create a schedule in which running progression and strength progression are designed together rather than independently generated and merged afterward.

### Plan inputs

- Athlete goals and relative priority.

- Race/event date and target when relevant.

- Current training baseline and recent history.

- Available training days and practical constraints.

- Desired or appropriate running and lifting frequency.

- Current strength and endurance capability estimates.

- Exercise preferences or exclusions and training environment constraints.

- Recent fatigue/context when supplied.

- Existing fixed sessions that the athlete chooses to preserve.

### Plan outputs

- A multi-week schedule containing individual running and strength sessions.

- Weekly running volume and meaningful intensity distribution.

- Long-run progression where appropriate.

- Appropriate key running sessions and supporting easy work.

- Strength frequency and exercise/session structure consistent with the selected strength goal.

- Progression, maintenance, deload, taper, or emphasis shifts when appropriate to the athlete’s block.

- Clear designation of the purpose of each workout.

- A plain-language summary of how the block balances running and strength priorities.

### Interference-aware rules

- Avoid repeatedly placing high-fatigue lower-body strength work immediately before the week’s most important running sessions when a reasonable alternative exists.

- Avoid unnecessary clustering of high-intensity running and high-fatigue lower-body lifting.

- Allow upper-body strength work to coexist with running more freely when the athlete can reasonably tolerate it.

- Adjust strength dose when endurance volume or race specificity becomes substantially more demanding.

- Adjust running dose when the athlete has explicitly chosen strength as the dominant priority.

- Respect the athlete’s real availability even when the theoretical schedule would be cleaner. When constraints force a compromise, explain it rather than hiding it.

- Use recovery/easy days intentionally rather than treating every available day as a training slot.

### Safety and realism constraints

- The product must avoid abrupt workload changes that are obviously inconsistent with the athlete’s recent baseline unless the athlete knowingly overrides the recommendation.

- It should avoid prescribing impossible combinations such as overlapping events, contradictory targets inside the same interval, or more sessions than available days can contain without an explicit two-a-day decision.

- It must distinguish training guidance from medical advice and avoid diagnosing injury or illness.

### Plan transparency

The athlete should be able to inspect the plan at weekly and block level and understand major choices such as why lower-body volume was reduced during peak running weeks or why a key run was separated from heavy leg training.

### Acceptance criteria

**✓** Given a complete athlete profile, hybrd can create a multi-week schedule containing both running and strength work.

**✓** The plan changes meaningfully when the athlete changes the relative priority from run-first to strength-first.

**✓** The plan does not merely overlay independent templates; session placement and dose reflect the presence of the other discipline.

**✓** When athlete availability forces a compromise, the product surfaces the compromise in understandable language.

**✓** The athlete can accept the generated plan, inspect it before acceptance, and make changes after acceptance.

**08 Adaptive progression**

*Use completed training to update future prescriptions instead of leaving the original plan frozen.*

### Purpose

The athlete’s plan should evolve as actual performance diverges from assumptions. Adaptation in the MVP should be conservative, understandable, and grounded in observable training outcomes.

### Running signals

- Completion versus planned distance/duration.

- Performance of prescribed work segments.

- Heart-rate response where available.

- RPE and subjective difficulty.

- Repeated over-performance or under-performance.

- Missed, shortened, or modified sessions.

- Recent volume and tolerance relative to the planned progression.

### Strength signals

- Reps and load achieved versus prescribed targets.

- RPE/RIR when available.

- Repeated ability or inability to progress a movement.

- Exercise substitutions.

- Incomplete sessions.

- Observed e1RM, volume, or rep-performance trend where meaningful.

### Adaptation outcomes

- Adjust future load, reps, sets, or effort targets in strength training.

- Adjust future running targets, volume, session difficulty, or progression rate.

- Hold progression when current work is not being tolerated.

- Reduce or simplify future work after meaningful missed/failed training rather than automatically compensating by stacking extra work.

- Preserve successful training when no change is necessary.

### Control and explainability

- Material changes should be presented with a reason.

- The athlete can reject or manually override a proposed change.

- The system should not change completed historical workouts when adapting future training.

- Adaptation should use trends where possible rather than overreacting to one anomalous session.

### Acceptance criteria

**✓** Repeated successful strength performance can lead to an appropriate future progression rather than identical prescriptions indefinitely.

**✓** Repeated difficulty completing a running prescription can lead to an adjusted future target or load.

**✓** A single poor workout does not automatically trigger a dramatic plan rewrite without corroborating context.

**✓** Every material adaptive change can be explained to the athlete in plain language.

**09 Unified performance dashboard**

*Show whether the athlete is progressing in running, strength, and overall training without requiring expert interpretation of dozens of metrics.*

### Purpose

The dashboard is a decision surface, not a data warehouse. It should help the athlete answer: Am I doing the plan? Is my running improving? Is my strength improving or being maintained? Is my training load changing in a way I should notice?

### Running view

- Weekly distance and frequency over time.

- Long-run progression.

- Intensity distribution at a useful summary level.

- Performance trend using stable comparable signals such as pace at effort/HR, benchmark performance, or other supported indicators.

- Planned versus completed running volume.

### Strength view

- Strength-session frequency.

- Exercise or key-lift performance trend.

- Estimated strength trend where supported.

- Volume/hard-set trend at a useful level.

- Planned versus completed strength work.

### Combined view

- Overall adherence/compliance to planned training.

- Total weekly training frequency and time where available.

- Combined training-load trend using a product-defined representation that does not imply false precision.

- Current block/week status: building, maintaining, deloading, tapering, or another relevant phase.

- Notable recent changes or tradeoffs, such as increasing run load while strength is intentionally maintained.

### Presentation rules

- Every primary metric should have a clear label and understandable interpretation.

- The dashboard should distinguish objective observations from model-derived estimates.

- Estimated metrics should show uncertainty or avoid excessive precision when the underlying data does not justify it.

- The athlete should be able to select a useful time range rather than viewing only lifetime totals.

### Acceptance criteria

**✓** Within one minute, an athlete can determine planned versus completed training for the current week.

**✓** The athlete can inspect separate running and strength progression without leaving the product’s overall training context.

**✓** The combined view does not imply that every strength and running stressor can be reduced to a perfectly equivalent single number.

**✓** No MVP dashboard metric exists only because it is available; each metric should support interpretation or training decisions.

**10 AI coach with athlete context**

*Provide a conversational interface that can explain the plan and analyze the athlete’s real training history without inventing context.*

### Purpose

The AI coach should make hybrd’s structured data and training logic easier to interrogate. It is an interface to the athlete’s training context, not a replacement for the underlying training model.

### The coach must be able to answer questions about

- The current training plan and why sessions are placed where they are.

- Recent running performance and trends.

- Recent strength performance and trends.

- Planned versus completed training.

- Potential interactions between upcoming running and strength sessions.

- Reasons behind recent adaptive changes.

- What changed over a user-specified time period.

- How a proposed schedule change may affect the current week or block.

- Basic explanations of product metrics and training concepts used by hybrd.

### Coach actions within MVP

- Propose a change to future training when the athlete asks for one.

- Explain the consequences/tradeoffs of that change.

- Present a clear summary of the proposed modifications before they alter the plan.

- Apply the modifications only when the athlete explicitly accepts the proposal or has initiated an unambiguous direct edit in the product.

### Grounding and trust requirements

- The coach must distinguish known athlete data from inference.

- If necessary data is missing, it should say what is missing rather than fabricating a result.

- When citing the athlete’s own performance, it should use the actual relevant time period and workout context.

- It should not claim medical certainty or diagnose injury, illness, overtraining syndrome, or other health conditions.

- It should not present speculative race or strength predictions as guarantees.

- It should be able to explain why it made a recommendation in plain language.

### Representative MVP questions

| **Field**                                               | **Requirement**                                                                                                                                                                     |
|---------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **“Why did my leg volume drop this week?”**             | Explain the relationship between the current running block, nearby key sessions, prior strength dose, and the intended goal priority.                                               |
| **“Am I actually getting faster?”**                     | Summarize recent comparable running evidence, note confounders, and describe the direction and confidence of the trend.                                                             |
| **“Move my lower session from Wednesday to Thursday.”** | Evaluate nearby sessions, identify meaningful conflict, propose the best available revised schedule, and wait for acceptance if the change affects more than the requested session. |
| **“Why has my bench stalled?”**                         | Use recent bench performance, set/repetition history, effort, frequency, and relevant plan context; acknowledge when the available evidence is insufficient.                        |
| **“Can I add another run?”**                            | Assess current schedule, volume, priority, and recent tolerance; explain tradeoffs and propose where/how to add it if reasonable.                                                   |

### Acceptance criteria

**✓** The coach can answer a question about a specific recent workout using the correct workout data.

**✓** The coach can explain a plan decision without relying on generic advice alone.

**✓** The coach does not modify the training calendar invisibly.

**✓** The coach explicitly communicates uncertainty when the product lacks enough athlete data to support a strong conclusion.

**11 Automatic replanning after real-life changes**

*Keep the plan coherent when the athlete misses, moves, shortens, or unexpectedly adds training.*

### Purpose

Real athletes do not execute calendars perfectly. The MVP must handle disruptions without forcing the athlete to manually solve the entire week or, conversely, automatically cram every missed workout into the remaining days.

### Replanning triggers

- A session is missed.

- A session is moved.

- The athlete marks one or more future days unavailable.

- A key run or strength session is partially completed.

- An unplanned high-load workout is added.

- The athlete asks the AI coach to change the week.

- The athlete becomes unavailable for multiple days.

### Required behavior

- Preserve the most important training objectives for the week where practical.

- Avoid automatically “making up” all missed volume if doing so creates a worse schedule.

- Remove, reduce, move, or replace lower-priority work when necessary.

- Protect recovery around key sessions where possible.

- Keep weekly and block-level progression understandable after the change.

- Show the athlete what changed relative to the prior plan.

- Explain material sacrifices, such as reducing weekly distance or removing lower-body accessory volume.

### User control

- A simple one-session move may apply immediately when it does not materially affect other sessions.

- When replanning changes multiple sessions or materially changes weekly dose, the athlete should see a proposed revision and be able to accept or reject it.

- The athlete may manually override the proposed solution.

### Acceptance criteria

**✓** Missing one session does not automatically cause the same full session to be stacked onto the next available day.

**✓** A multi-day availability change produces a coherent revised week that clearly identifies removed, moved, or altered work.

**✓** The product preserves completed history and records that the future plan was revised.

**✓** The athlete can compare the revised week with the practical training objective it is trying to preserve.

# 6. Cross-feature product behavior

### Planned versus actual must remain distinct

Every workout should preserve both the prescription and the completed result. Editing future plans must not rewrite completed history. Imported performance should not erase what the athlete was originally asked to do.

### Manual edits coexist with automation

The athlete may manually edit the plan. hybrd should treat deliberate user edits as real constraints and avoid repeatedly undoing them without explanation. When a subsequent automated change conflicts with a deliberate edit, the conflict should be surfaced.

### Confidence and uncertainty

Not every metric or inference has equal certainty. The product should avoid false precision and distinguish directly observed data, athlete-reported data, and derived estimates where that distinction matters to interpretation.

### Change history

For material plan changes, the athlete should be able to understand what changed and why. The MVP does not require a complex version-control interface, but it does require enough traceability that adaptations do not feel arbitrary.

### Time and calendar integrity

Activities and plans must retain the athlete-relevant date and sequence in which they occurred. Travel, time-zone changes, late-night workouts, or imported timestamps should not casually move completed sessions to the wrong training day.

### Incomplete data

hybrd should degrade gracefully. Missing HR, pace segments, RPE, historical strength data, or other optional fields should reduce confidence or available analysis rather than making the core training record unusable.

# 7. Data and user-control requirements

These are product-level requirements for trust and portability. They intentionally do not prescribe storage, security architecture, or integration mechanisms.

| **Field**                            | **Requirement**                                                                                                                                                                                                                               |
|--------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Ownership expectation**            | The athlete should be able to view the training information hybrd uses about them and understand its source at a practical level.                                                                                                             |
| **Correction**                       | The athlete can correct profile information, workout matching, and manually entered training data.                                                                                                                                            |
| **Deletion**                         | The athlete can remove manually created workouts and disconnect external data sources. Account-level deletion behavior should be defined before public launch.                                                                                |
| **Export**                           | The product should preserve the future possibility of exporting an athlete’s core training record in a useful format. Full export is not required for the first internal build, but the data model should not conceptually depend on lock-in. |
| **Source attribution**               | Where useful, imported activities can be identified as coming from an external source versus being created directly in hybrd.                                                                                                                 |
| **Sensitive interpretation**         | Training and recovery information should not be framed as a medical diagnosis. Health-adjacent signals must use careful language.                                                                                                             |
| **Consent for external connections** | Connecting or disconnecting an external source is an explicit athlete action.                                                                                                                                                                 |
| **Automation control**               | Material plan modifications are visible and reversible through normal product editing even when they were proposed by automation or AI.                                                                                                       |

# 8. MVP success criteria

### Product success

- A new hybrid athlete can reach a credible first coordinated plan without having to manually construct both disciplines.

- The athlete can execute a full week of running and lifting using hybrd as the central planning record.

- The athlete does not need a separate lifting logger to capture the data hybrd needs for progression.

- Externally recorded runs can contribute to the plan and analytics without duplicate manual entry.

- When real life disrupts the week, hybrd helps repair the schedule rather than making the calendar less useful.

- The AI coach can answer athlete-specific questions that would be impossible to answer correctly from generic fitness knowledge alone.

- After several weeks, the product can show meaningful evidence about both running and strength progression or maintenance.

### Quality bar

- **Trust.** The athlete can tell what is planned, what happened, and why the future plan changed.

- **Speed.** Common workout actions do not require excessive navigation or repeated data entry.

- **Coherence.** Running and lifting prescriptions do not routinely contradict one another.

- **Graceful imperfection.** Missing data, missed workouts, substitutions, and schedule changes do not break the training record.

- **Useful specificity.** The product provides more individualized guidance than a static hybrid template while avoiding unjustified certainty.

# 9. Explicitly out of scope for MVP

The following may become valuable later but should not be required to ship the P0 product defined above.

| **Field**                             | **Requirement**                                                                                                                                                  |
|---------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Social network**                    | Feeds, followers, likes, clubs, public activity discovery, challenges, and segment competition.                                                                  |
| **Nutrition system**                  | Meal logging, calorie counting, macros, recipes, or fueling commerce.                                                                                            |
| **Recovery wearable replacement**     | Native sleep sensing, HRV sensing, continuous physiological monitoring, or a proprietary wearable.                                                               |
| **Route ecosystem**                   | Advanced route creation, heat maps, live navigation, or location-based segment discovery.                                                                        |
| **Form analysis**                     | Computer-vision lifting form critique or running-gait video analysis.                                                                                            |
| **Coach marketplace**                 | Discovering, hiring, billing, or messaging human coaches.                                                                                                        |
| **Broad multisport support**          | Cycling, swimming, rowing, CrossFit, HYROX, skiing, team sports, etc. may be represented as context later but are not first-class programmed disciplines in MVP. |
| **Advanced race ecosystem**           | Race discovery, registration, travel planning, or race marketplace features.                                                                                     |
| **Gamification layer**                | Badges, streak economy, competitive leaderboards, virtual currencies, or deep challenge systems.                                                                 |
| **Full professional analytics suite** | Every advanced chart, custom formula, data field, and dashboard expected by sports scientists or elite coaching organizations.                                   |
| **Medical/injury management**         | Diagnosis, rehabilitation protocols, return-to-play clearance, or clinical decision support.                                                                     |

# 10. MVP+ differentiators and roadmap boundary

These capabilities are strategically important because they could create a stronger edge in a crowded category. They are deliberately separated from the P0 launch scope so the implementation plan can estimate them independently.

### A. Programmable athlete interface / MCP-style agent access

Allow the athlete to connect an external capable agent to a controlled hybrd interface. The external agent should be able to retrieve the athlete’s authorized training context and, with explicit athlete permission, propose or perform supported training-plan actions.

- Read athlete profile, goals, plan, recent training, progress, and relevant analytics.

- Query workouts over specified time windows.

- Create a proposed workout or training block.

- Move, modify, or remove future workouts within athlete-granted permissions.

- Run a validation step that identifies scheduling conflicts or incompatible prescriptions before applying changes.

- Present a clear record of actions performed by an external agent.

- Allow the athlete to revoke external-agent access.

> **Strategic distinction**
>
> The differentiated opportunity is not merely “hybrd supports MCP.” The stronger product concept is that hybrd becomes the athlete’s canonical, programmable training context and safe action layer, while the athlete may choose the intelligence that operates on top of it.

### B. Workout-to-device delivery

Allow structured workouts created in hybrd to appear on supported training devices so the athlete can execute sessions without manually recreating intervals or targets on the device.

### C. Hybrid interference visualization

Expose the interaction model directly to the athlete: show when one session may materially compromise another, which body regions or performance qualities are most affected, and what alternative scheduling choices reduce the conflict.

### D. Combined fatigue model

Represent systemic, cardiovascular, and muscle-specific training stress separately enough to explain why two sessions with similar duration may have very different implications for the next workout.

### E. Goal tradeoff modeling

Allow the athlete to compare different training emphases—for example, run-priority versus balanced—so they can see how frequency, volume, progression, and expected compromises would differ before committing to a block.

### F. Training simulation

Allow the athlete to ask “what if?” questions about planned changes—such as adding a leg day, increasing weekly distance, or moving a long run—and see the predicted scheduling and load implications before changing the live plan.

### G. Formal testing and recalibration

Periodically prescribe benchmark sessions that improve the quality of the athlete model, such as threshold/critical-speed tests, time trials, AMRAPs, or submaximal strength benchmarks, then use the results to update training targets.

### H. Human coach workspace

Allow a coach to manage multiple athletes, inspect hybrid-training status, identify athletes needing attention, adjust plans, and use the same analysis/AI capabilities while retaining coach approval and accountability.

# 11. Open product decisions for implementation planning

These questions should be answered during the next design/engineering discussion because they materially affect scope, but this document intentionally does not prescribe the implementation.

**1.** How many weeks must the first generated plan contain, and how far into the future should the athlete be able to inspect/edit?

**2.** What is the minimum historical window required for useful baseline reconstruction?

**3.** Which running workout types are mandatory for the first public release versus later?

**4.** Which strength progression styles must the MVP support beyond basic set/rep/load progression?

**5.** How should the athlete express training priority: categorical options, a continuous scale, or both?

**6.** What constitutes a “material” scheduling conflict worthy of a warning versus normal concurrent training?

**7.** When should a calendar edit apply immediately versus trigger a multi-session replan proposal?

**8.** How much plan adaptation should occur automatically after a workout versus at defined review points?

**9.** Which dashboard metrics are sufficiently reliable and decision-useful to ship at launch?

**10.** Which external activity sources are required for initial market viability?

**11.** How should the product represent low-confidence imported or inferred data to the athlete?

**12.** What actions, if any, should the AI coach be allowed to apply without an explicit confirmation step?

**13.** What minimum functionality is required offline or in poor connectivity during an active strength workout?

**14.** Which athlete types should the product explicitly reject or redirect at onboarding because the MVP cannot yet serve them safely or well?

**15.** What exact boundary will separate training guidance from health/medical guidance in the user experience?

# Implementation handoff summary

> **Build the “what” below**
>
> A user can define simultaneous running and strength goals, receive one coordinated plan, execute both kinds of workouts with purpose-built tracking, import prior/external training, see progress across both disciplines, receive conservative adaptive changes, repair the plan when life disrupts it, and ask an AI coach questions grounded in the athlete’s actual history and schedule.

### The defining test

If a user can obtain the same practical experience by running a good running app and a good lifting logger side-by-side, hybrd has not yet delivered its core value. The MVP succeeds when the coordination layer—planning, interference awareness, adaptation, replanning, and explanation—makes the combined program meaningfully better than two independent tools.
