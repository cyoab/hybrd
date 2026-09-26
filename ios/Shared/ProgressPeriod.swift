import Foundation

enum ProgressPeriod: Int, CaseIterable, Identifiable {
  case week = 7, month = 28, quarter = 84
  var id: Int { rawValue }
  var title: String {
    switch self { case .week: L10n.text("7 days"); case .month: L10n.text("4 weeks"); case .quarter: L10n.text("12 weeks") }
  }
  var comparisonLabel: String { L10n.text("vs previous \(rawValue) days") }
}
