import Foundation

enum OnboardingReadiness: String, CaseIterable, Codable, Identifiable {
  case ready, returning, adjusting
  var id: String { rawValue }
  var title: String {
    switch self {
    case .ready: L10n.text("Ready to build")
    case .returning: L10n.text("Finding my rhythm again")
    case .adjusting: L10n.text("I need some flexibility")
    }
  }
  var detail: String {
    switch self {
    case .ready: L10n.text("I’m training regularly and ready for structure.")
    case .returning: L10n.text("I’m starting fresh or coming back after a break.")
    case .adjusting: L10n.text("My energy, schedule, or physical limitations can vary.")
    }
  }
  var symbol: String {
    switch self { case .ready: "sun.max"; case .returning: "arrow.trianglehead.clockwise"; case .adjusting: "leaf" }
  }
}
