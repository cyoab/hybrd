import Foundation

/// Presentation snapshot of measured work. Missing distance goals never become estimates.
struct RunLiveMetrics {
  var pace: Double?
  var paceIsLast: Bool
  var averagePace: Double?
  var heartRate: Double?
  var zone: HeartRateZone?
  var remainingMeters: Double?
  var remainingSeconds: Double?

  init(run: RunRecording, at date: Date, currentPace: Double?) {
    let last = run.lastPace.flatMap { $0.isValid ? $0 : nil }
    let age = last.map { date.timeIntervalSince($0.recordedAt) }
    let fresh = !run.isPaused && !run.isFinished && (age.map { (0...12).contains($0) } ?? true)
    let live = currentPace.flatMap { fresh && $0.isFinite && $0 > 0 ? $0 : nil }
    pace = live ?? last?.secondsPerKilometer
    paceIsLast = live == nil && pace != nil

    let active = run.seconds(at: date)
    averagePace = run.meters.isFinite && run.meters >= 10 && active.isFinite && active > 0
      ? active * 1_000 / run.meters : nil
    heartRate = run.currentHeartRate(at: date)
    zone = heartRate.flatMap(run.zone)
    remainingMeters = run.workout.distanceMeters > 0
      ? max(0, Double(run.workout.distanceMeters) - run.meters) : nil
    let sequence = RunTimeline(segments: run.workout.segments).totalSeconds
    let duration = sequence > 0 ? Double(sequence) : Double(max(0, run.workout.minutes)) * 60
    remainingSeconds = remainingMeters == nil && duration > 0
      ? max(0, duration - active - run.intervalOffset) : nil
  }
}
