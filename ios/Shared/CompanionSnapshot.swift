import Foundation

struct CompanionSnapshot: Codable {
  var name: String
  var isSample: Bool
  var workouts: [TrainingWorkout]
  var updatedAt = Date()
  var heartRateZones: PersonalHeartRateZones?
  var units: TrainingUnits?
  var athleteID: UUID?
  var accountSignedOut: Bool?
  var hasAccountPlan: Bool { athleteID != nil && !isSample && accountSignedOut != true }
  static func signedOut() -> CompanionSnapshot {
    CompanionSnapshot(name: "", isSample: false, workouts: [], accountSignedOut: true)
  }
}
