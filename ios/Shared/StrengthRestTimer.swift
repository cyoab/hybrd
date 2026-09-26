import Foundation

struct StrengthRestTimer: Codable, Equatable {
  var duration: Double
  var endsAt: Date
  var exerciseName: String
  func remaining(at date: Date) -> Double { max(0, endsAt.timeIntervalSince(date)) }
  var fraction: Double { min(1, remaining(at: Date()) / max(1, duration)) }
  mutating func extend(by seconds: Double) { endsAt = max(endsAt, Date()).addingTimeInterval(seconds); duration += seconds }
}
