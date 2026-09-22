import Foundation

enum RunWorkoutChecks {
  static func run() throws {
    let date = Calendar.current.startOfDay(for: Date())
    let expectedMinutes: [RunWorkoutTemplate: Int] = [.easyThirty: 30, .recoveryTwenty: 20, .longSixty: 60,
      .tempoRepeats: 36, .steadyTempo: 30, .twoMinuteIntervals: 36, .hillRepeats: 30, .progression: 35]
    for template in RunWorkoutTemplate.allCases {
      let workout = template.workout(on: date)
      let second = template.workout(on: date)
      let timeline = RunTimeline(segments: workout.segments)
      precondition(workout.minutes == expectedMinutes[template])
      precondition(timeline.totalSeconds == workout.minutes * 60)
      precondition(SessionBreakdown(workout: workout).total == timeline.totalSeconds)
      precondition(workout.segments.allSatisfy { $0.seconds > 0 && $0.heartRateZone != nil })
      precondition(workout.segments.first?.phase == .warmUp && workout.segments.last?.phase == .coolDown)
      precondition(workout.distanceMeters == 0 && !workout.summary.contains("0.0 km"), "Time-based recipes must not invent distance")
      precondition(workout.id != second.id && workout.logicalID != second.logicalID)
      precondition(Set(workout.segments.map(\.id)).isDisjoint(with: Set(second.segments.map(\.id))))
      let decoded = try JSONDecoder().decode(TrainingWorkout.self, from: JSONEncoder().encode(workout))
      precondition(decoded == workout && decoded.resolvedRunType == template.type)
      let draft = WorkoutDraft(workout: workout)
      precondition(draft.distanceKilometers == 0 && draft.durationMinutes == 0, "Templates never prefill actual results")
    }
    precondition(Set(RunWorkoutTemplate.allCases.map(\.type)).count == 7)
    let intervals = RunWorkoutTemplate.twoMinuteIntervals.workout(on: date)
    let phases = RunTimeline(segments: intervals.segments).steps.map { $0.segment.phase }
    precondition(phases == [.warmUp] + Array(repeating: [RunSegmentPhase.work, .recovery], count: 6).flatMap { $0 } + [.coolDown])
    let progression = RunWorkoutTemplate.progression.workout(on: date)
    precondition(progression.primaryHeartRateZone == .four)
    precondition(progression.prescriptionTarget == "Z3–Z4 work", "Progression cards must show the range of work targets")
    let oldPlan = SampleTraining.makePlan(profile: TrainingProfile(), start: date)
    for workout in oldPlan.workouts.filter({ $0.kind == .run }) {
      var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(workout)) as! [String: Any]
      legacy.removeValue(forKey: "runType")
      let decoded = try JSONDecoder().decode(TrainingWorkout.self, from: JSONSerialization.data(withJSONObject: legacy))
      precondition(decoded.runType == nil && decoded.resolvedRunType == workout.runType)
      precondition(decoded.segments == workout.segments && decoded.id == workout.id)
    }
    var unknown = intervals
    unknown.runType = nil
    unknown.title = "Athlete's custom session"
    precondition(unknown.resolvedRunType == .custom, "Unknown old sessions must not be guessed from their HR targets")
    let historicalWorkouts = oldPlan.workouts
    let newPlan = TrainingEngine.adding(intervals, to: oldPlan)
    precondition(newPlan.id != oldPlan.id && newPlan.basePlanID == oldPlan.id)
    precondition(newPlan.workouts.count == oldPlan.workouts.count + 1)
    precondition(oldPlan.workouts == historicalWorkouts, "Historical snapshots must remain exact")
    precondition(newPlan.workouts.dropLast().map(\.logicalID) == oldPlan.workouts.map(\.logicalID))
    precondition(Set(newPlan.workouts.map(\.id)).isDisjoint(with: Set(oldPlan.workouts.map(\.id))),
      "New plan versions require new physical prescription IDs")
    for (old, revised) in zip(oldPlan.workouts, newPlan.workouts) {
      precondition(old.date == revised.date && old.title == revised.title && old.minutes == revised.minutes)
      precondition(old.distanceMeters == revised.distanceMeters && old.runType == revised.runType)
      precondition(old.segments.map(\.heartRateZone) == revised.segments.map(\.heartRateZone))
      precondition(old.segments.map(\.totalSeconds) == revised.segments.map(\.totalSeconds))
    }
    precondition(Set(oldPlan.workouts.flatMap(\.segments).map(\.id)).isDisjoint(with:
      Set(newPlan.workouts.dropLast().flatMap(\.segments).map(\.id))))
    precondition(Set(oldPlan.workouts.flatMap(\.exercises).flatMap(\.sets).map(\.id)).isDisjoint(with:
      Set(newPlan.workouts.dropLast().flatMap(\.exercises).flatMap(\.sets).map(\.id))))
    precondition(newPlan.workouts.last == intervals)
    precondition(newPlan.profile == oldPlan.profile)
    let roundTrip = try JSONDecoder().decode(TrainingPlan.self, from: JSONEncoder().encode(newPlan))
    precondition(roundTrip.workouts == newPlan.workouts)
    let summary = WeeklyTrainingSummary(workouts: newPlan.workouts, results: [])
    precondition(summary.timedRuns == 1 && summary.loggedMeters == 0)
    precondition(summary.plannedMeters == WeeklyTrainingSummary(workouts: oldPlan.workouts, results: []).plannedMeters)
    let starter = TrainingEngine.makePlan(profile: TrainingProfile(), start: date)
    precondition(starter.workouts.filter { $0.kind == .run }.allSatisfy { [.easy, .long].contains($0.runType) },
      "Harder templates remain an explicit choice, never an automatic starter-plan escalation")
    print("PASS: run recipes, durations, repetitions, HR ranges, legacy run categories, template identity, immutable additions, time-based totals, and unchanged starter intensity")
  }
}
