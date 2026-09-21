import Foundation

struct CompanionSnapshot: Codable {
  var name: String
  var isSample: Bool
  var workouts: [TrainingWorkout]
  var updatedAt = Date()
}
