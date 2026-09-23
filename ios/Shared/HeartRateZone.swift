import Foundation

/// Relative five-zone prescription targets. Personal BPM boundaries are not inferred.
enum HeartRateZone: Int, Codable, CaseIterable, Identifiable, Comparable {
  case one = 1, two, three, four, five

  var id: Int { rawValue }
  var title: String { L10n.text("Zone \(rawValue)") }
  var shortTitle: String { L10n.text("Z\(rawValue)") }

  var name: String {
    switch self {
    case .one: L10n.text("Recovery")
    case .two: L10n.text("Easy")
    case .three: L10n.text("Steady")
    case .four: L10n.text("Hard")
    case .five: L10n.text("Peak")
    }
  }

  static func < (lhs: HeartRateZone, rhs: HeartRateZone) -> Bool { lhs.rawValue < rhs.rawValue }
}
