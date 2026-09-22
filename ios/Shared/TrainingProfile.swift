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

  var validationMessage: String? {
    guard weeklyKilometers.isFinite, (3...150).contains(weeklyKilometers) else {
      return "Enter a weekly distance from 3 to 150 km."
    }
    guard availableDays.count >= 2, availableDays.isSubset(of: Set(1...7)) else {
      return "Choose at least two valid training days."
    }
    guard (1...4).contains(strengthDays), [30, 45, 60, 75, 90].contains(sessionMinutes) else {
      return "Choose a strength frequency and session length from the available options."
    }
    return nil
  }

  static func parseWeeklyKilometers(_ text: String, locale: Locale = .current) -> Double? {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.isLenient = false
    let separator = formatter.decimalSeparator ?? "."
    let parts = input.components(separatedBy: separator)
    guard parts.count <= 2, input.contains(where: { $0.isNumber }),
          parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
          let number = formatter.number(from: input)?.doubleValue,
          number.isFinite, (3...150).contains(number) else { return nil }
    return number
  }
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
