import Foundation

struct TrainingPlan: Codable, Identifiable {
  var id = UUID()
  var basePlanID: UUID?
  var createdAt = Date()
  var reason: String
  var profile: TrainingProfile
  var workouts: [TrainingWorkout]
}
