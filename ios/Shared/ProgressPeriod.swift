import Foundation

enum ProgressPeriod: Int, CaseIterable, Identifiable {
  case week = 7, month = 28, quarter = 84
  var id: Int { rawValue }
  var title: String {
    switch self { case .week: "7 days"; case .month: "4 weeks"; case .quarter: "12 weeks" }
  }
  var comparisonLabel: String { "vs previous \(rawValue) days" }
}
