import Foundation

/// Preferences only. All actuals, prescriptions and HealthKit data stay in meters/kg.
struct TrainingUnits: Codable, Equatable {
  var weight: TrainingWeightUnit = .kilograms
  var distance: TrainingDistanceUnit = .kilometers
  static let metric = TrainingUnits()

  func distanceNumber(_ meters: Double, decimals: Int = 1) -> String {
    distance.value(fromMeters: meters).formatted(.number.precision(.fractionLength(0...decimals)))
  }
  func distanceText(_ meters: Double, decimals: Int = 1) -> String {
    distanceNumber(meters, decimals: decimals) + " " + distance.symbol
  }
  func weightNumber(_ kilograms: Double, decimals: Int = 1) -> String {
    weight.value(fromKilograms: kilograms).formatted(.number.precision(.fractionLength(0...decimals)))
  }
  func weightText(_ kilograms: Double) -> String { weightNumber(kilograms) + " " + weight.symbol }
  func weightInput(_ kilograms: Double) -> String {
    weight.value(fromKilograms: kilograms).formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
  }
  func distanceInput(_ meters: Double) -> String {
    distance.value(fromMeters: meters).formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
  }
  func paceNumber(_ secondsPerKilometer: Double?) -> String {
    guard let value = secondsPerKilometer, value.isFinite, value > 0, value < 3_600 else { return "—" }
    // Validate the canonical pace before conversion; a valid slow pace can exceed
    // an hour per mile and should still display rather than become unavailable.
    return RunRecording.clock(distance.pace(fromSecondsPerKilometer: value).rounded())
  }
  func paceText(_ secondsPerKilometer: Double?) -> String { paceNumber(secondsPerKilometer) + " /" + distance.symbol }
  func summary(_ workout: TrainingWorkout) -> String {
    guard workout.kind == .run else { return workout.summary }
    guard workout.distanceMeters > 0 else { return "\(workout.minutes) min · Time-based run" }
    return distanceText(Double(workout.distanceMeters)) + " · \(workout.minutes) min"
  }
  func lapTitle(_ lap: RunLap) -> String { lap.kind == .manual ? "Lap \(lap.number)" : "Split \(lap.number)" }
}
