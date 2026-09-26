import Foundation

/// Actual activity matched to the selected week's prescriptions by logical identity.
struct WeeklyTrainingSummary {
  var plannedMeters: Int
  var loggedMeters: Int
  var timedRuns: Int
  var plannedLifts: Int
  var loggedLifts: Int

  init(workouts: [TrainingWorkout], results: [WorkoutResult]) {
    let recorded = workouts.compactMap { workout in
      results.first { $0.logicalWorkoutID == workout.logicalID && $0.status != .skipped }
    }
    timedRuns = workouts.filter { $0.kind == .run && $0.distanceMeters == 0 }.count
    plannedMeters = workouts.filter { $0.kind == .run }.reduce(0) { $0 + $1.distanceMeters }
    loggedMeters = recorded.filter { $0.kind == .run }.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
    plannedLifts = workouts.filter { $0.kind == .strength }.count
    loggedLifts = recorded.filter { $0.kind == .strength }.count
  }

  var runningProgress: Double {
    plannedMeters > 0 ? min(1, max(0, Double(loggedMeters) / Double(plannedMeters))) : 0
  }

  var liftingProgress: Double {
    plannedLifts > 0 ? min(1, max(0, Double(loggedLifts) / Double(plannedLifts))) : 0
  }
}
