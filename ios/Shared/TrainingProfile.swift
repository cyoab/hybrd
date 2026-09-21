import Foundation

struct TrainingProfile: Codable, Equatable {
  var name = "Athlete"
  var runningGoal: RunningGoal = .halfMarathon
  var strengthGoal: StrengthGoal = .build
  var priority: TrainingPriority = .balanced
  var availableDays: Set<Int> = [2, 3, 4, 5, 6, 7]
  var weeklyKilometers = 24.0
  var strengthDays = 3
  var sessionMinutes = 60
  var isSample = true
}

enum RunningGoal: String, CaseIterable, Codable, Identifiable {
  case fitness = "General fitness"
  case fiveK = "5K"
  case tenK = "10K"
  case halfMarathon = "Half marathon"
  case marathon = "Marathon"
  var id: String { rawValue }
}

enum StrengthGoal: String, CaseIterable, Codable, Identifiable {
  case build = "Build strength"
  case muscle = "Build muscle"
  case maintain = "Maintain strength"
  var id: String { rawValue }
}

enum TrainingPriority: String, CaseIterable, Codable, Identifiable {
  case balanced = "Balanced"
  case running = "Running first"
  case strength = "Strength first"
  var id: String { rawValue }
}
