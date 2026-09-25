import Foundation

/// Reissues only known, unstarted built-in recipes; never converts an RPE number to a zone.
enum HeartRatePlanUpgrade {
  static func apply(to plan: TrainingPlan, retaining protectedIDs: Set<UUID>, today: Date = Date()) -> TrainingPlan? {
    let start = Calendar.current.startOfDay(for: today)
    var changed = false
    let workouts = plan.workouts.map { workout -> TrainingWorkout in
      guard workout.kind == .run, workout.date >= start, !protectedIDs.contains(workout.logicalID),
            workout.segments.contains(where: { $0.heartRateZone == nil }),
            isBuiltInRecipe(workout, isSample: plan.profile.isSample) else { return workout }
      var updated = workout
      updated.segments = workout.segments.map { segment in
        var part = segment
        if part.heartRateZone == nil {
          let phase = part.phase ?? legacyPhase(part.title)
          part.phase = phase
          switch phase {
          case .warmUp, .easy: part.heartRateZone = .two
          case .work, .stride: part.heartRateZone = .four
          case .recovery, .coolDown: part.heartRateZone = .one
          case nil: break
          }
        }
        return part
      }
      guard updated != workout else { return workout }
      changed = true
      return updated.reidentified()
    }
    guard changed else { return nil }
    var updated = plan
    updated.id = UUID()
    updated.basePlanID = plan.id
    updated.createdAt = today
    updated.change = nil
    updated.reason = "Heart-rate targets added to upcoming built-in runs"
    updated.workouts = workouts
    return updated
  }

  private static func isBuiltInRecipe(_ workout: TrainingWorkout, isSample: Bool) -> Bool {
    let phases = workout.segments.map { $0.phase ?? legacyPhase($0.title) }
    if isSample && workout.title == "Threshold intervals" {
      return phases == [.warmUp, .work, .recovery, .coolDown]
        && workout.segments.map(\.title) == ["Warm-up", "Work", "Recovery", "Cool-down"]
    }
    return ["Aerobic base", "Long easy run", "Easy run"].contains(workout.title)
      && phases == [.warmUp, .easy, .coolDown]
      && [["Ease in", "Easy running", "Cool down"], ["Warm-up", "Easy running", "Cool-down"]]
        .contains(workout.segments.map(\.title))
  }

  private static func legacyPhase(_ title: String) -> RunSegmentPhase? {
    switch title {
    case "Ease in", "Warm-up": .warmUp
    case "Easy running": .easy
    case "Cool down", "Cool-down": .coolDown
    default: nil
    }
  }
}
