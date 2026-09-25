import Foundation

struct TrainingPlan: Codable, Identifiable {
  var id = UUID()
  var basePlanID: UUID?
  var createdAt = Date()
  var reason: String
  var change: Change?
  var localizedReason: String {
    guard let change else { return L10n.content(reason) }
    let title = L10n.content(change.workoutTitle)
    let date = change.date.formatted(date: .abbreviated, time: .omitted)
    switch change.kind {
    case .added: return L10n.text("Added \(title) on \(date)")
    case .moved: return L10n.text("Moved \(title) to \(date)")
    }
  }

  struct Change: Codable {
    enum Kind: String, Codable { case added, moved }
    var kind: Kind
    var workoutTitle: String
    var date: Date
  }
  var profile: TrainingProfile
  var workouts: [TrainingWorkout]
  var projectionVersion: Int?
}
