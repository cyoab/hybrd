import Foundation

/// Descriptive comparisons of logged, matched efforts; never a fitness estimate.
struct ProgressComparison: Identifiable {
  var kind: WorkoutKind
  var title: String
  var subtitle: String
  var points: [Point]
  var id: String { kind.rawValue + title + subtitle }
  var latestDate: Date { points.last!.date }
  var best: Point { points.min { kind == .run ? $0.value < $1.value : $0.value > $1.value }! }
  var first: Double { points.first!.value }
  var latest: Double { points.last!.value }
  var improved: Bool { kind == .run ? latest < first : latest > first }
  var change: Double { abs(latest - first) }
  var changeLabel: String {
    guard change > (kind == .run ? 0.5 : 0.01) else { return "Holding steady" }
    if kind == .run {
      return "\(Int(change.rounded())) sec/km " + (improved ? "faster" : "slower")
    }
    return "\(change.formatted(.number.precision(.fractionLength(0...1)))) kg " + (improved ? "more" : "less")
  }
  func formatted(_ value: Double) -> String {
    kind == .run ? RunningPersonalBest.format(Int(value.rounded())) + " /km" :
      value.formatted(.number.precision(.fractionLength(0...1))) + " kg"
  }
  struct Point: Identifiable {
    var resultID: UUID
    var date: Date
    var value: Double
    var id: UUID { resultID }
  }
}
