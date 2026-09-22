import Foundation

enum RunWorkoutType: String, Codable, CaseIterable, Identifiable {
  case easy, recovery, long, tempo, intervals, hills, progression, custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .easy: "Easy run"
    case .recovery: "Recovery run"
    case .long: "Long run"
    case .tempo: "Tempo"
    case .intervals: "Intervals"
    case .hills: "Hills"
    case .progression: "Progression"
    case .custom: "Run"
    }
  }

  var symbol: String {
    switch self {
    case .easy: "leaf"
    case .recovery: "wind"
    case .long: "road.lanes"
    case .tempo: "speedometer"
    case .intervals: "repeat"
    case .hills: "mountain.2"
    case .progression: "chart.line.uptrend.xyaxis"
    case .custom: "figure.run"
    }
  }

  /// Presentation fallback for known older recipes; never rewrites their prescriptions.
  static func legacyType(for title: String) -> Self {
    switch title {
    case "Aerobic base", "Easy run": .easy
    case "Long easy run": .long
    case "Threshold intervals": .intervals
    default: .custom
    }
  }
}
