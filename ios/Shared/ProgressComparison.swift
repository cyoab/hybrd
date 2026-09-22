import Foundation

/// Descriptive comparisons of logged, matched efforts; never a fitness estimate.
struct ProgressComparison: Identifiable {
  var kind: WorkoutKind
  var title: String
  var subtitle: String
  var points: [Point]
  var runDistanceMeters: Int?
  var runType: RunWorkoutType?
  var id: String { kind.rawValue + title + subtitle }
  var latestDate: Date { points.last!.date }
  var best: Point { points.min { kind == .run ? $0.value < $1.value : $0.value > $1.value }! }
  var first: Double { points.first!.value }
  var latest: Double { points.last!.value }
  var improved: Bool { kind == .run ? latest < first : latest > first }
  var change: Double { abs(latest - first) }
  var changeLabel: String { changeLabel(in: .metric) }
  func displayTitle(in units: TrainingUnits) -> String {
    guard let meters = runDistanceMeters, let runType else { return title }
    return units.distanceText(Double(meters), decimals: 3) + " · " + runType.title
  }
  func displayValue(_ value: Double, in units: TrainingUnits) -> Double {
    kind == .run ? units.distance.pace(fromSecondsPerKilometer: value) : units.weight.value(fromKilograms: value)
  }
  func changeLabel(in units: TrainingUnits) -> String {
    guard change > (kind == .run ? 0.5 : 0.01) else { return "Holding steady" }
    if kind == .run {
      return "\(Int(displayValue(change, in: units).rounded())) sec/" + units.distance.symbol + (improved ? " faster" : " slower")
    }
    return units.weightText(change) + (improved ? " more" : " less")
  }
  func formatted(_ value: Double, units: TrainingUnits = .metric) -> String {
    kind == .run ? units.paceText(value) : units.weightText(value)
  }
  struct Point: Identifiable {
    var resultID: UUID
    var date: Date
    var value: Double
    var id: UUID { resultID }
  }
}
