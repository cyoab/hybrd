import Foundation

/// Device/per-app language selection is owned by the OS. Storage remains language independent.
enum L10n {
  static let supportedLanguages = ["en", "es", "pt-BR", "fr"]

  static func text(_ value: String.LocalizationValue, bundle: Bundle = .main, locale: Locale = .current) -> String {
    String(localized: value, bundle: bundle, locale: locale)
  }

  /// Built-in prescription text and enum labels use their original English as stable keys.
  /// Unknown names (including user-entered names) pass through unchanged.
  static func content(_ key: String, bundle: Bundle = .main) -> String {
    bundle.localizedString(forKey: key, value: key, table: "Localizable")
  }
}
