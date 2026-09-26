import Foundation

/// Last measured pace, retained across GPS loss, pauses and checkpoint recovery.
struct RunPaceReading: Codable, Equatable {
  var secondsPerKilometer: Double
  var recordedAt: Date

  var isValid: Bool {
    secondsPerKilometer.isFinite && secondsPerKilometer > 0 && recordedAt.timeIntervalSinceReferenceDate.isFinite
  }
}
