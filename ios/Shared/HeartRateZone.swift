import Foundation

/// Relative five-zone prescription targets. Personal BPM boundaries are not inferred.
enum HeartRateZone: Int, Codable, CaseIterable, Identifiable, Comparable {
  case one = 1, two, three, four, five

  var id: Int { rawValue }
  var title: String { "Zone \(rawValue)" }
  var shortTitle: String { "Z\(rawValue)" }

  var name: String {
    switch self {
    case .one: "Recovery"
    case .two: "Easy"
    case .three: "Steady"
    case .four: "Hard"
    case .five: "Peak"
    }
  }

  static func < (lhs: HeartRateZone, rhs: HeartRateZone) -> Bool { lhs.rawValue < rhs.rawValue }
}
