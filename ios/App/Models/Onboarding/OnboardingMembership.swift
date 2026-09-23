import Foundation

/// Display-only offers. A preview choice never grants a subscription entitlement.
enum OnboardingMembership: String, CaseIterable, Codable, Identifiable {
  case annual, monthly
  var id: String { rawValue }
  var cents: Int { self == .annual ? 9_999 : 1_099 }
  var title: String { self == .annual ? L10n.text("Annual") : L10n.text("Monthly") }
  var price: String { Self.price(cents: cents) }
  var billing: String { self == .annual ? L10n.text("Billed annually") : L10n.text("Billed monthly") }
  var equivalent: String {
    self == .annual ? L10n.text("\(Self.price(cents: 833)) / month equivalent") : L10n.text("A flexible monthly commitment")
  }
  static var annualSavingsPercent: Int { Int((1 - Double(annual.cents) / Double(monthly.cents * 12)) * 100) }
  static func price(cents: Int) -> String {
    "US$" + (Double(cents) / 100).formatted(.number.precision(.fractionLength(2)))
  }
}
