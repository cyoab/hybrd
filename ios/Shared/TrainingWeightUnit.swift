import Foundation

enum TrainingWeightUnit: String, Codable, CaseIterable, Identifiable {
  case kilograms, pounds
  var id: String { rawValue }
  var symbol: String { self == .kilograms ? "kg" : "lb" }
  var title: String { self == .kilograms ? "Kilograms" : "Pounds" }
  private var kilogramsPerUnit: Double { self == .kilograms ? 1 : 0.45359237 }
  func value(fromKilograms value: Double) -> Double { value / kilogramsPerUnit }
  func kilograms(from value: Double) -> Double { value * kilogramsPerUnit }
  func parse(_ text: String, kilograms range: ClosedRange<Double>, locale: Locale = .current) -> Double? {
    guard let input = TrainingProfile.parseDecimal(text, range: 0...Double.greatestFiniteMagnitude, locale: locale) else { return nil }
    let value = kilograms(from: input)
    guard value.isFinite, value >= range.lowerBound - 1e-9, value <= range.upperBound + 1e-9 else { return nil }
    return min(range.upperBound, max(range.lowerBound, value))
  }
}
