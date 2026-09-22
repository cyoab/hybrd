import SwiftUI

enum WatchRunStyle {
  static let terra = Color(red: 1, green: 0.48, blue: 0.3)
  static let mint = Color(red: 0.45, green: 0.85, blue: 0.68)
  static let violet = Color(red: 0.76, green: 0.65, blue: 0.97)

  static func zoneColor(_ zone: HeartRateZone) -> Color {
    switch zone { case .one: .cyan; case .two: mint; case .three: .yellow; case .four: terra; case .five: violet }
  }
  static func workoutColor(_ workout: TrainingWorkout) -> Color {
    guard workout.kind == .run else { return violet }
    return switch workout.resolvedRunType {
    case .easy: Color(red: 0.70, green: 0.82, blue: 0.37)
    case .recovery: .cyan
    case .long: violet
    case .tempo: .yellow
    case .intervals, .custom: terra
    case .hills: mint
    case .progression: Color(red: 0.45, green: 0.84, blue: 0.81)
    }
  }
}
