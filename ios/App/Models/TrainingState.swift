import Foundation

struct TrainingState: Codable {
  var schemaVersion = 1
  var profile: TrainingProfile
  var plans: [TrainingPlan]
  var results: [WorkoutResult] = []
  var drafts: [WorkoutDraft] = []
  var messages: [CoachMessage] = []

  /// No account data is manufactured before authenticated hydration.
  /// The empty plan only preserves the store's nonoptional plan invariant.
  static func empty() -> TrainingState {
    let profile = TrainingProfile(name: "", runningGoal: .fitness, availableDays: [], weeklyKilometers: 0,
      strengthDays: 0, sessionMinutes: 45, isSample: false)
    return TrainingState(profile: profile, plans: [TrainingPlan(reason: "", profile: profile, workouts: [])])
  }
}

struct CoachMessage: Codable, Identifiable {
  var id = UUID()
  var text: String
  var isAthlete: Bool
  var date = Date()
}
