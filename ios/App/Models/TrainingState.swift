import Foundation

struct TrainingState: Codable {
  var schemaVersion = 1
  var profile: TrainingProfile
  var plans: [TrainingPlan]
  var results: [WorkoutResult] = []
  var drafts: [WorkoutDraft] = []
  var messages: [CoachMessage] = []

  static func sample() -> TrainingState {
    let profile = TrainingProfile()
    return TrainingState(profile: profile, plans: [SampleTraining.makePlan(profile: profile)])
  }
}

struct CoachMessage: Codable, Identifiable {
  var id = UUID()
  var text: String
  var isAthlete: Bool
  var date = Date()
}
