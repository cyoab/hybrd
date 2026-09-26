import Foundation

enum OnboardingHeightUnit: String, CaseIterable, Codable, Identifiable {
  case centimeters, feetAndInches
  var id: String { rawValue }
  var title: String {
    switch self {
    case .centimeters: L10n.text("Centimeters")
    case .feetAndInches: L10n.text("Feet & inches")
    }
  }
}
