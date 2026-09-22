import SwiftUI

/// A device-local display preference, independent of the athlete's training profile.
enum AppAppearance: String, CaseIterable, Identifiable {
  case light
  case dark
  case system

  static let storageKey = "hybrd.appearance"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .light: "Light"
    case .dark: "Dark"
    case .system: "System"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .light: .light
    case .dark: .dark
    case .system: nil
    }
  }
}
