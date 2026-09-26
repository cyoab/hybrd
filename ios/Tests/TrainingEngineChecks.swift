import Foundation

@main
enum TrainingEngineChecks {
  @MainActor static func main() async throws {
    try ExecutablePrescriptionChecks.run()
    try await AgentIntegrationChecks.run()
    try AccountEntryChecks.run()
    try await BackendConnectionChecks.run()
    try await BackendLiveChecks.run()
    try await BackendOnboardingChecks.run()
    try OnboardingChecks.run()
    try LocalizationChecks.run()
    try TrainingUnitsChecks.run()
    try LiveWorkoutChecks.run()
    try RunLiveMetricsChecks.run()
    ProgressChecks.run()
    HomePlanChecks.run()
    try RunWorkoutChecks.run()
    try AthleteProfileChecks.run()
    let english = Locale(identifier: "en_US")
    let german = Locale(identifier: "de_DE")
    precondition(TrainingProfile.parseWeeklyKilometers("70", locale: english) == 70)
    precondition(TrainingProfile.parseWeeklyKilometers(" 70.5 ", locale: english) == 70.5)
    precondition(TrainingProfile.parseWeeklyKilometers("70,5", locale: german) == 70.5)
    for input in ["", "70km", "70x", "NaN", "inf", "-4", "151", "2.9", "7.0.5", "70,5"] {
      precondition(TrainingProfile.parseWeeklyKilometers(input, locale: english) == nil,
        "Reject malformed or out-of-range distances instead of silently changing them: " + input)
    }
    for boundary in ["3", "150"] {
      precondition(TrainingProfile.parseWeeklyKilometers(boundary, locale: english) != nil)
    }
    var profile = TrainingProfile()
    profile.weeklyKilometers = .infinity
    precondition(profile.validationMessage != nil, "Reject non-finite distances before planning")
    profile.weeklyKilometers = 70.5
    precondition(profile.validationMessage == nil)
    profile.availableDays = [2]
    precondition(profile.validationMessage != nil)
    profile.availableDays = [2, 8]
    precondition(profile.validationMessage != nil, "Reject invalid weekday values")
    profile.availableDays = [2, 4, 6]
    profile.strengthDays = 2
    let start = ISO8601DateFormatter().date(from: "2026-09-21T12:00:00Z")!
    let plan = TrainingEngine.makePlan(profile: profile, start: start)
    precondition(plan.workouts.count == 12, "Four weeks must respect three available days")
    precondition(plan.workouts.allSatisfy {
      profile.availableDays.contains(Calendar.current.component(.weekday, from: $0.date))
    }, "Never schedule on unavailable days")
    precondition(Set(plan.workouts.map(\.id)).count == plan.workouts.count)
    precondition(Set(plan.workouts.map(\.logicalID)).count == plan.workouts.count)

    let original = plan.workouts[0]
    let moved = TrainingEngine.moving(original, to: TrainingEngine.date(start, offset: 1), in: plan)
    precondition(moved.id != plan.id && moved.basePlanID == plan.id)
    precondition(moved.workouts.map(\.logicalID) == plan.workouts.map(\.logicalID), "Logical identities survive plan revisions")
    precondition(Set(moved.workouts.map(\.id)).isDisjoint(with: Set(plan.workouts.map(\.id))), "Physical prescription IDs must be new")
    precondition(plan.workouts[0].date == original.date, "Moving must not mutate historical snapshots")
    let originalSetIDs = Set(plan.workouts.flatMap(\.exercises).flatMap(\.sets).map(\.id))
    let movedSetIDs = Set(moved.workouts.flatMap(\.exercises).flatMap(\.sets).map(\.id))
    precondition(originalSetIDs.isDisjoint(with: movedSetIDs), "Nested prescriptions must also get new IDs")
    precondition(!TrainingEngine.conflicts(for: original, on: plan.workouts[1].date, in: plan).isEmpty)

    let runDraft = WorkoutDraft(workout: original)
    precondition(runDraft.distanceKilometers == 0 && runDraft.durationMinutes == 0, "Prescriptions are not actual results")
    let lift = plan.workouts.first { $0.kind == .strength }!
    let draft = WorkoutDraft(workout: lift)
    precondition(draft.sets.allSatisfy { !$0.isComplete }, "No sets are performed by default")
    precondition(draft.sets.compactMap(\.prescriptionID) == lift.exercises.flatMap(\.sets).map(\.id))

    var logged = draft
    logged.resume(at: start)
    logged.pause(at: start.addingTimeInterval(60))
    logged.resume(at: start.addingTimeInterval(600))
    logged.pause(at: start.addingTimeInterval(630))
    precondition(logged.activeSeconds() == 90, "Paused time must not count as performed work")
    for index in logged.sets.indices { logged.sets[index].isComplete = true }
    precondition(logged.canFinish && logged.hasAllPrescribedSets)
    logged.sets.removeFirst()
    precondition(logged.canFinish && !logged.hasAllPrescribedSets, "Removed prescribed sets make a session partial")
    let count = logged.sets.count
    logged.addSet(for: lift.exercises[0])
    precondition(logged.sets.count == count + 1 && logged.sets.last?.prescriptionID == nil)
    precondition(logged.sets.last?.isComplete == false, "Extra sets require explicit completion")
    logged.sets[0].kilograms = -1
    precondition(!logged.canFinish, "Negative completed loads must be rejected")

    var runLog = runDraft
    runLog.distanceKilometers = 0.000001
    runLog.durationMinutes = 30
    precondition(!runLog.canFinish, "A run must contain at least one meter of actual distance")
    runLog.distanceKilometers = 5
    precondition(runLog.canFinish)
    var legacyDraft = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
    legacyDraft.removeValue(forKey: "elapsedSeconds")
    legacyDraft.removeValue(forKey: "runningSince")
    let restoredDraft = try JSONDecoder().decode(WorkoutDraft.self, from: JSONSerialization.data(withJSONObject: legacyDraft))
    precondition(restoredDraft.sets == draft.sets && restoredDraft.activeSeconds() == 0)

    let restored = try JSONDecoder().decode(TrainingPlan.self, from: JSONEncoder().encode(moved))
    precondition(restored.id == moved.id && restored.workouts == moved.workouts)
    // Optional presentation metadata must not break existing persisted training.
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
    legacy.removeValue(forKey: "scheduledMinutes")
    legacy.removeValue(forKey: "isOptional")
    let legacyWorkout = try JSONDecoder().decode(TrainingWorkout.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(legacyWorkout.id == original.id && legacyWorkout.scheduledMinutes == nil)
    let sample = SampleTraining.makePlan(profile: profile, start: start)
    precondition(sample.workouts.filter { $0.kind == .run }.allSatisfy {
      $0.segments.reduce(0) { $0 + $1.totalSeconds } == $0.minutes * 60
    }, "Displayed interval totals must equal prescribed duration")
    precondition(sample.workouts.contains { $0.isOptional == true })
    let intervals = sample.workouts.first { $0.segments.contains { $0.phase == .work } }!
    let timeline = RunTimeline(segments: intervals.segments)
    precondition(timeline.steps.map { $0.segment.phase } == [
      .warmUp, .work, .recovery, .work, .recovery, .work, .recovery, .coolDown
    ], "Repeated work and recovery must alternate chronologically")
    precondition(timeline.totalSeconds == intervals.minutes * 60)
    precondition(timeline.steps.first?.startSeconds == 0)
    for pair in zip(timeline.steps, timeline.steps.dropFirst()) {
      precondition(pair.0.endSeconds == pair.1.startSeconds, "Timeline must not overlap or omit time")
    }
    let easy = RunTimeline(segments: original.segments)
    precondition(easy.totalSeconds == original.minutes * 60, "Legacy untyped phases still visualize correctly")
    precondition(RunTimeline(segments: []).steps.isEmpty)
    let unpaired = RunTimeline(segments: [RunSegment(title: "Strides", seconds: 20, cue: "Relaxed", phase: .work, repetitions: 4)])
    precondition(unpaired.steps.count == 4 && unpaired.totalSeconds == 80)
    let composition = SessionBreakdown(workout: intervals)
    precondition(composition.total == 58 * 60)
    precondition(composition.parts.first { $0.id == "zone1" }?.amount == 19 * 60)
    precondition(composition.parts.first { $0.id == "zone4" }?.amount == 24 * 60)
    precondition(composition.parts.first { $0.id == "zone2" }?.amount == 15 * 60)
    precondition(abs(composition.parts.reduce(0.0) { $0 + composition.share(of: $1) } - 1) < 0.000001,
      "Infographic shares must account for the entire prescribed session")
    var legacyRun = original
    legacyRun.segments = original.segments.map { segment in
      var old = segment
      old.phase = nil
      old.heartRateZone = nil
      return old
    }
    let legacyComposition = SessionBreakdown(workout: legacyRun)
    precondition(legacyComposition.parts.count == 1 && legacyComposition.parts[0].id == "unassigned",
      "Do not infer HR targets from missing metadata or legacy RPE")
    precondition(legacyComposition.total == RunTimeline(segments: legacyRun.segments).totalSeconds)
    precondition(composition.value(for: 80) == "1:20" && composition.unit(for: 80) == "min:sec",
      "Sub-minute prescriptions must not lose seconds in the infographic")
    var unevenLift = lift
    unevenLift.exercises[0].sets.removeLast()
    let setComposition = SessionBreakdown(workout: unevenLift)
    precondition(setComposition.parts.map(\.amount) == unevenLift.exercises.map { $0.sets.count })
    precondition(setComposition.total == unevenLift.exercises.flatMap(\.sets).count,
      "Strength composition must show prescribed set counts, not estimated muscle loading")
    var emptyRun = original
    emptyRun.segments = []
    precondition(SessionBreakdown(workout: emptyRun).total == 0)
    precondition(SessionBreakdown(workout: emptyRun).parts.isEmpty)
    var emptyLift = lift
    emptyLift.exercises = []
    precondition(SessionBreakdown(workout: emptyLift).total == 0)
    precondition(intervals.primaryHeartRateZone == .four && !intervals.prescriptionTarget.contains("RPE"))
    precondition(original.primaryHeartRateZone == .two)
    let encodedRun = try JSONEncoder().encode(intervals)
    let restoredRun = try JSONDecoder().decode(TrainingWorkout.self, from: encodedRun)
    precondition(restoredRun.segments.map(\.heartRateZone) == intervals.segments.map(\.heartRateZone))
    var legacySegment = try JSONSerialization.jsonObject(with: JSONEncoder().encode(intervals.segments[0])) as! [String: Any]
    legacySegment.removeValue(forKey: "heartRateZone")
    let decodedSegment = try JSONDecoder().decode(RunSegment.self, from: JSONSerialization.data(withJSONObject: legacySegment))
    precondition(decodedSegment.heartRateZone == nil, "Existing persisted segments must decode without zone metadata")

    var legacyPlan = sample
    legacyPlan.workouts = sample.workouts.map { workout in
      var old = workout
      old.segments = workout.segments.map { segment in
        var part = segment
        part.heartRateZone = nil
        return part
      }
      return old
    }
    let protectedRun = legacyPlan.workouts.first { $0.kind == .run }!
    let beforeUpgrade = try JSONEncoder().encode(legacyPlan)
    let upgrade = HeartRatePlanUpgrade.apply(to: legacyPlan, retaining: [protectedRun.logicalID], today: start)!
    precondition(upgrade.id != legacyPlan.id && upgrade.basePlanID == legacyPlan.id)
    precondition(upgrade.workouts.first { $0.logicalID == protectedRun.logicalID } == protectedRun,
      "Completed and in-progress prescriptions must remain exact")
    precondition(legacyPlan.workouts.allSatisfy { $0.segments.allSatisfy { $0.heartRateZone == nil } },
      "Upgrading targets must not mutate a historical snapshot")
    precondition(upgrade.workouts.contains { $0.primaryHeartRateZone == .four })
    precondition(HeartRatePlanUpgrade.apply(to: upgrade, retaining: [protectedRun.logicalID], today: start) == nil,
      "Target upgrade must be idempotent")
    let historicalPlan = try JSONDecoder().decode(TrainingPlan.self, from: beforeUpgrade)
    precondition(historicalPlan.workouts == legacyPlan.workouts)
    var custom = legacyPlan
    custom.workouts = [protectedRun]
    custom.workouts[0].title = "Custom coach workout"
    precondition(HeartRatePlanUpgrade.apply(to: custom, retaining: [], today: start) == nil,
      "Never assign guessed zones to an unknown recipe")
    precondition(HeartRatePlanUpgrade.apply(to: legacyPlan, retaining: [], today: TrainingEngine.date(start, offset: 40)) == nil,
      "Past sessions must retain their original targets")
    var legacyStarter = plan
    legacyStarter.workouts = plan.workouts.map { workout in
      var old = workout
      old.segments = workout.segments.map { segment in
        var part = segment
        part.phase = nil
        part.heartRateZone = nil
        return part
      }
      return old
    }
    let starterUpgrade = HeartRatePlanUpgrade.apply(to: legacyStarter, retaining: [], today: start)!
    precondition(starterUpgrade.workouts.filter { $0.kind == .run }.allSatisfy { $0.primaryHeartRateZone == .two })
    print("PASS: HR targets, Codable compatibility, safe plan upgrades, zone composition totals and shares, profile input and validation, interval ordering and duration, planning invariants, legacy decoding, actual-result validation, partial/extra sets, and pause/resume timing")
  }
}
