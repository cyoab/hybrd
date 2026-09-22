import Foundation
import HealthKit

@MainActor
final class HealthProfileReader {
  private let store = HKHealthStore()
  static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  func requestImport() async throws -> HealthProfileImport {
    guard Self.isAvailable else { throw HealthImportError.unavailable }
    let weight = HKQuantityType(.bodyMass)
    let height = HKQuantityType(.height)
    let birth = HKCharacteristicType(.dateOfBirth)
    // No write access, activity history, or unrelated health data is requested.
    try await store.requestAuthorization(toShare: [], read: [weight, height, birth])
    let components = try? store.dateOfBirthComponents()
    let birthDate = components.flatMap { Calendar(identifier: .gregorian).date(from: $0) }
    async let mass = latest(weight, unit: .gramUnit(with: .kilo), range: 20...400)
    async let stature = latest(height, unit: .meterUnit(with: .centi), range: 80...250)
    var result = try await HealthProfileImport(birthDate: birthDate, weight: mass, height: stature)
    if let birthDate = result.birthDate {
      let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? -1
      if birthDate > Date() || !(0...120).contains(age) { result.birthDate = nil }
    }
    return result
  }

  private func latest(_ type: HKQuantityType, unit: HKUnit, range: ClosedRange<Double>) async throws -> HealthMeasurement? {
    try await withCheckedThrowingContinuation { continuation in
      let query = HKSampleQuery(sampleType: type,
        predicate: HKQuery.predicateForSamples(withStart: nil, end: Date(), options: .strictEndDate),
        limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
        if let error { continuation.resume(throwing: error); return }
        guard let sample = samples?.first as? HKQuantitySample else { continuation.resume(returning: nil); return }
        let value = sample.quantity.doubleValue(for: unit)
        continuation.resume(returning: value.isFinite && range.contains(value) ? HealthMeasurement(value: value, date: sample.endDate) : nil)
      }
      store.execute(query)
    }
  }
}

struct HealthProfileImport: Identifiable {
  var id = UUID()
  var birthDate: Date?
  var weight: HealthMeasurement?
  var height: HealthMeasurement?
  var isEmpty: Bool { birthDate == nil && weight == nil && height == nil }
}

struct HealthMeasurement {
  var value: Double
  var date: Date
}

private enum HealthImportError: LocalizedError {
  case unavailable
  var errorDescription: String? { "Apple Health isn’t available on this device. You can enter your details manually." }
}
