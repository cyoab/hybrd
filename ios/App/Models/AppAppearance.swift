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
    case .light: L10n.text("Light")
    case .dark: L10n.text("Dark")
    case .system: L10n.text("System")
    }
  }

  var symbol: String {
    switch self {
    case .light: "sun.max.fill"
    case .dark: "moon.fill"
    case .system: "circle.lefthalf.filled"
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
