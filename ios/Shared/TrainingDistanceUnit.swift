import Foundation

enum TrainingDistanceUnit: String, Codable, CaseIterable, Identifiable {
  case kilometers, miles
  var id: String { rawValue }
  var symbol: String { self == .kilometers ? "km" : "mi" }
  var title: String { self == .kilometers ? "Kilometers" : "Miles" }
  var singular: String { self == .kilometers ? "kilometer" : "mile" }
  var metersPerUnit: Double { self == .kilometers ? 1_000 : 1_609.344 }
  func value(fromMeters value: Double) -> Double { value / metersPerUnit }
  func meters(from value: Double) -> Double { value * metersPerUnit }
  func pace(fromSecondsPerKilometer value: Double) -> Double { value * metersPerUnit / 1_000 }
  func parse(_ text: String, meters range: ClosedRange<Double>, locale: Locale = .current) -> Double? {
    guard let input = TrainingProfile.parseDecimal(text, range: 0...Double.greatestFiniteMagnitude, locale: locale) else { return nil }
    let value = meters(from: input)
    guard value.isFinite, value >= range.lowerBound - 1e-7, value <= range.upperBound + 1e-7 else { return nil }
    return min(range.upperBound, max(range.lowerBound, value))
  }
}
