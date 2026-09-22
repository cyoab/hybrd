import Foundation

/// Durable actuals owned by the device that starts the workout. No prescribed values become actuals.
struct RunRecording: Codable, Identifiable, Equatable {
  enum Source: String, Codable { case phone = "iPhone", watch = "Apple Watch" }
  var id = UUID()
  var workout: TrainingWorkout
  var zones: PersonalHeartRateZones?
  var source: Source
  var recordedTimeZoneID: String? = TimeZone.current.identifier
  var startedAt: Date
  var runningSince: Date?
  var elapsed: Double = 0
  var checkpointAt: Date
  var endedAt: Date?
  var meters: Double = 0
  var route: [RunLocation] = []
  var laps: [RunLap] = []
  var heartRate: Double?
  var heartRateAt: Date?
  var averageHeartRate: Double?
  var maximumHeartRate: Double?
  var healthWorkoutID: UUID?
  var healthSaveMessage: String?
  var recoveryMessage: String?
  var intervalOffset: Double = 0
  var kilometerMark: Int = 0
  var kilometerTime: Double = 0
  var manualLapMeters: Double = 0
  var manualLapTime: Double = 0
  var distanceSampleTime: Double = 0

  var isPaused: Bool { runningSince == nil && endedAt == nil }
  var isFinished: Bool { endedAt != nil }
  var averagePace: Double? { meters >= 10 && elapsed > 0 ? elapsed * 1_000 / meters : nil }
  var canSave: Bool { elapsed.isFinite && startedAt.timeIntervalSinceReferenceDate.isFinite && (endedAt.map { $0.timeIntervalSinceReferenceDate.isFinite && $0 >= startedAt } ?? true) && meters.isFinite && (1...500_000).contains(meters) && elapsed >= 1 && elapsed <= 172_800 }

  func seconds(at date: Date = Date()) -> Double {
    elapsed + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
  }
  mutating func pause(at date: Date) {
    elapsed = seconds(at: date); runningSince = nil; checkpointAt = date
  }
  mutating func resume(at date: Date) {
    guard endedAt == nil, runningSince == nil else { return }
    runningSince = date; checkpointAt = date
  }
  mutating func finish(at date: Date) {
    pause(at: date); endedAt = date
  }
  func step(at date: Date) -> RunTimeline.Step? {
    let time = seconds(at: date) + intervalOffset
    return RunTimeline(segments: workout.segments).steps.first { Double($0.endSeconds) > time }
  }
  mutating func advanceStep(at date: Date) {
    guard let current = step(at: date), !isPaused, !isFinished else { return }
    intervalOffset += max(0, Double(current.endSeconds) - seconds(at: date) - intervalOffset)
  }
  mutating func updateDistance(_ total: Double, at seconds: Double) {
    guard total.isFinite, total >= meters, total <= 500_000, seconds >= distanceSampleTime else { return }
    let oldDistance = meters
    let oldTime = distanceSampleTime
    while Double(kilometerMark + 1) * 1_000 <= total {
      let boundary = Double(kilometerMark + 1) * 1_000
      let fraction = total > oldDistance ? (boundary - oldDistance) / (total - oldDistance) : 1
      let crossing = oldTime + (seconds - oldTime) * min(1, max(0, fraction))
      kilometerMark += 1
      laps.append(RunLap(kind: .kilometer, number: kilometerMark, meters: 1_000, seconds: max(0, crossing - kilometerTime)))
      kilometerTime = crossing
    }
    meters = total; distanceSampleTime = seconds
  }
  // Keep dependent reads inside the value mutation. Reading an @Observable optional
  // again from the call site while mutating it violates Swift exclusivity.
  mutating func updateFinalDistance(_ total: Double) {
    updateDistance(total, at: elapsed)
  }
  mutating func markHealthSaveFailure() {
    healthSaveMessage = healthWorkoutID == nil
      ? "Saved locally. Apple Health couldn’t save this workout."
      : "Workout saved to Apple Health; its route could not be saved."
  }
  mutating func markLap(at date: Date) {
    guard !isPaused, !isFinished else { return }
    let time = seconds(at: date)
    guard time - manualLapTime >= 1 else { return }
    laps.append(RunLap(kind: .manual, number: laps.filter { $0.kind == .manual }.count + 1,
      meters: max(0, meters - manualLapMeters), seconds: time - manualLapTime))
    manualLapMeters = meters; manualLapTime = time
  }
  func currentHeartRate(at date: Date) -> Double? {
    guard !isPaused, !isFinished, let heartRateAt, date.timeIntervalSince(heartRateAt) <= 20 else { return nil }
    return heartRate
  }
  func zone(for bpm: Double) -> HeartRateZone? {
    guard let zones, zones.isValid else { return nil }
    return HeartRateZone(rawValue: zones.starts.filter { bpm >= Double($0) }.count + 1)
  }
  func result() -> WorkoutResult {
    WorkoutResult(id: id, plannedWorkoutID: workout.id, logicalWorkoutID: workout.logicalID,
      completedAt: endedAt ?? checkpointAt, kind: .run, status: .completed,
      durationSeconds: Int(elapsed.rounded()), distanceMeters: Int(meters.rounded()), effort: 0,
      notes: "Recorded on " + source.rawValue, sets: [], run: self)
  }
  static func clock(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "—" }
    let value = max(0, Int(seconds))
    return value >= 3_600 ? String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
  }
  static func pace(_ secondsPerKM: Double?) -> String {
    guard let value = secondsPerKM, value.isFinite, value > 0, value < 3_600 else { return "—" }
    return clock(value.rounded())
  }
}

struct RunLap: Codable, Identifiable, Equatable {
  enum Kind: String, Codable { case kilometer, manual }
  var id = UUID()
  var kind: Kind
  var number: Int
  var meters: Double
  var seconds: Double
  var title: String { kind == .kilometer ? "Kilometer \(number)" : "Lap \(number)" }
  var pace: Double? { meters > 0 ? seconds * 1_000 / meters : nil }
}

struct RunLocation: Codable, Equatable {
  var latitude: Double
  var longitude: Double
  var altitude: Double
  var accuracy: Double
  var timestamp: Date
  var startsSegment = false
}
