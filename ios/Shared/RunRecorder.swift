import Foundation
import Observation
import HealthKit
import CoreLocation
#if os(watchOS)
import WatchKit
#endif

@MainActor @Observable
final class RunRecorder: NSObject, CLLocationManagerDelegate, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
  static let shared = RunRecorder()
  private(set) var recording: RunRecording?
  private(set) var preparing = false
  private(set) var ending = false
  private(set) var currentPace: Double?
  private(set) var gpsMessage = L10n.text("GPS not started")
  private(set) var lastLocationAt: Date?
  private(set) var cue = 0
  var errorMessage: String?
  @ObservationIgnored private let health = HKHealthStore()
  @ObservationIgnored private let location = CLLocationManager()
  @ObservationIgnored private var session: HKWorkoutSession?
  @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
  @ObservationIgnored private var gpsFilter = RunGPSFilter()
  @ObservationIgnored private var speeds: [Double] = []
  @ObservationIgnored private var timer: Timer?
  @ObservationIgnored private var permission: CheckedContinuation<Bool, Never>?
  @ObservationIgnored private var lastCheckpoint = Date.distantPast
  @ObservationIgnored private var previousStep: Int?
  @ObservationIgnored private var finalizing = false
  @ObservationIgnored private var routeCheckpointCount = 0
  @ObservationIgnored private var recoveryAttempted = false

  override init() {
    super.init()
    recording = RunArchive.loadActive()
    routeCheckpointCount = recording?.route.count ?? 0
    if recording == nil && RunArchive.hasCheckpoint { errorMessage = L10n.text("A saved run could not be read. It has been preserved and will not be overwritten.") }
    location.delegate = self
    location.activityType = .fitness
    location.desiredAccuracy = kCLLocationAccuracyBest
    location.distanceFilter = 3
    #if os(iOS)
    location.pausesLocationUpdatesAutomatically = false
    #endif
  }

  func start(_ workout: TrainingWorkout, zones: PersonalHeartRateZones?, units: TrainingUnits = .metric) async {
    guard recording == nil, !preparing, !RunArchive.hasCheckpoint else { return }
    if let issue = workout.executionIssue { errorMessage = issue; return }
    preparing = true; errorMessage = nil
    defer { preparing = false }
    do {
      guard HKHealthStore.isHealthDataAvailable() else { throw RecorderError.message(L10n.text("Apple Health isn’t available on this device. You can still log a completed run on iPhone.")) }
      let distance = HKQuantityType(.distanceWalkingRunning)
      try await health.requestAuthorization(toShare: [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), distance],
        read: [HKQuantityType(.heartRate), distance, HKObjectType.workoutType()])
      guard health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
        throw RecorderError.message(L10n.text("Allow hybrd to save workouts in Apple Health to start recording, or log your completed run manually on iPhone."))
      }
      let granted = await locationPermission()
      guard granted, location.accuracyAuthorization == .fullAccuracy else {
        throw RecorderError.message(L10n.text("Enable Precise Location for hybrd in Settings to record an outdoor run."))
      }
      let config = HKWorkoutConfiguration(); config.activityType = .running; config.locationType = .outdoor
      let session = try HKWorkoutSession(healthStore: health, configuration: config)
      attach(session)
      let start = Date()
      #if os(watchOS)
      let source: RunRecording.Source = .watch
      #else
      let source: RunRecording.Source = .phone
      #endif
      routeCheckpointCount = 0
      recording = RunRecording(workout: workout, zones: zones, source: source, splitUnit: units.distance, startedAt: start, runningSince: start, checkpointAt: start)
      guard checkpoint() else { recording = nil; builder?.discardWorkout(); session.end(); self.session = nil; return }
      try await builder?.addMetadata([HKMetadataKeyExternalUUID: recording!.id.uuidString, "hybrd.logicalWorkoutID": workout.logicalID.uuidString])
      session.startActivity(with: start)
      if let builder { try await collect(builder, start: start) }
      startSensors()
    } catch {
      errorMessage = error.localizedDescription
      if var value = recording { value.pause(at: Date()); value.recoveryMessage = "Recording was interrupted during start. Finish this record or discard it before starting again."; recording = value; checkpoint() }
      session?.end(); builder?.discardWorkout(); session = nil; builder = nil
    }
  }

  private func collect(_ builder: HKLiveWorkoutBuilder, start: Date? = nil, end: Date? = nil) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let completion: @Sendable (Bool, Error?) -> Void = { success, error in
        if let error { continuation.resume(throwing: error) }
        else if success { continuation.resume() }
        else { continuation.resume(throwing: RecorderError.message(L10n.text("Apple Health could not update workout recording."))) }
      }
      if let start { builder.beginCollection(withStart: start, completion: completion) }
      else if let end { builder.endCollection(withEnd: end, completion: completion) }
      else { continuation.resume() }
    }
  }

  private func attach(_ session: HKWorkoutSession) {
    self.session = session; session.delegate = self
    let builder = session.associatedWorkoutBuilder()
    self.builder = builder; builder.delegate = self
    let source = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: session.workoutConfiguration)
    #if os(iOS)
    // iPhone owns GPS distance. Do not mix it with a second pedometer distance stream.
    source.disableCollection(for: HKQuantityType(.distanceWalkingRunning))
    #endif
    builder.dataSource = source
  }

  func recover() async {
    guard !recoveryAttempted, session == nil, !preparing else { return }
    recoveryAttempted = true
    guard let saved = recording else { return }
    preparing = true
    ending = saved.isFinished
    defer { preparing = false; ending = false }
    do {
      let recovered = try await health.recoverActiveWorkoutSession()
      if saved.isFinished {
        if let existing = try? await savedHealthWorkout(id: saved.id) {
          recording?.healthWorkoutID = existing.uuid
          recording?.healthSaveMessage = "Saved to Apple Health"
          recovered?.end()
        } else if let recovered {
          attach(recovered)
          await finishCollection(at: saved.endedAt ?? saved.checkpointAt)
        } else if saved.healthWorkoutID == nil {
          recording?.healthSaveMessage = "Your measurements are safe locally. Apple Health saving could not be confirmed after the interruption."
        }
        checkpoint()
        return
      }
      if let recovered {
        attach(recovered)
        recording?.elapsed = recovered.associatedWorkoutBuilder().elapsedTime(at: Date())
        recording?.runningSince = recovered.state == .running ? Date() : nil
        recording?.recoveryMessage = "Workout recovered. GPS gaps are excluded from the route."
        if recovered.state == .running { startSensors() }
        else if recovered.state == .stopped || recovered.state == .ended { await finishCollection(at: recovered.endDate ?? Date()) }
        checkpoint()
      } else {
        recording?.pause(at: saved.checkpointAt)
        recording?.recoveryMessage = "Recovered through the last saved checkpoint. Review and save this run; untracked time has not been added."
        checkpoint()
      }
    } catch {
      recording?.pause(at: saved.checkpointAt)
      recording?.recoveryMessage = "The live session could not be recovered. Your saved measurements are ready to review."
      errorMessage = error.localizedDescription; checkpoint()
    }
  }

  private func savedHealthWorkout(id: UUID) async throws -> HKWorkout? {
    try await withCheckedThrowingContinuation { continuation in
      let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [id.uuidString])
      let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: samples?.first as? HKWorkout) }
      }
      health.execute(query)
    }
  }

  private func locationPermission() async -> Bool {
    switch location.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse: return true
    case .notDetermined:
      return await withCheckedContinuation { continuation in permission = continuation; location.requestWhenInUseAuthorization() }
    default: return false
    }
  }
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    Task { @MainActor in
      if status != .notDetermined {
        self.permission?.resume(returning: status == .authorizedAlways || status == .authorizedWhenInUse); self.permission = nil
      }
      if status == .denied || status == .restricted {
        self.gpsMessage = L10n.text("Location unavailable"); self.currentPace = nil; self.gpsFilter.reset()
      }
    }
  }
  private func startSensors() {
    gpsFilter.reset(); speeds = []; currentPace = nil; gpsMessage = L10n.text("Finding GPS…")
    #if os(iOS)
    location.allowsBackgroundLocationUpdates = true
    location.showsBackgroundLocationIndicator = true
    #endif
    location.startUpdatingLocation()
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    previousStep = recording?.step(at: Date())?.id
  }
  private func stopSensors() {
    location.stopUpdatingLocation(); gpsFilter.reset(); speeds = []; currentPace = nil
    timer?.invalidate(); timer = nil
  }
  private func tick() {
    recording?.observeExecution(at: Date())
    guard let value = recording, !value.isPaused, !value.isFinished else { return }
    let step = value.step(at: Date())?.id
    if step != previousStep { previousStep = step; feedback() }
    if lastLocationAt.map({ Date().timeIntervalSince($0) > 12 }) ?? true { currentPace = nil; gpsMessage = L10n.text("Waiting for GPS") }
    if Date().timeIntervalSince(lastCheckpoint) >= 5 { checkpoint() }
  }
  func pauseOrResume() {
    guard let value = recording, !value.isFinished, !ending else { return }
    guard let session else { errorMessage = L10n.text("This recovered record is ready to finish. Start a new run after saving it."); return }
    if value.isPaused { session.resume() } else { session.pause() }
  }
  func lap() { recording?.markLap(at: Date()); checkpoint(); feedback() }
  func nextInterval() { recording?.advanceStep(at: Date()); previousStep = recording?.step(at: Date())?.id; checkpoint(); feedback() }
  func finish() {
    guard recording != nil, recording?.isFinished == false, !ending, !preparing else { return }
    ending = true
    if let session, session.state == .running || session.state == .paused { session.stopActivity(with: Date()) }
    else { Task { await finishCollection(at: recording?.checkpointAt ?? Date()) } }
  }
  private func finishCollection(at end: Date) async {
    guard !finalizing, recording != nil else { return }
    finalizing = true; ending = true
    stopSensors()
    recording?.finish(at: end)
    checkpoint()
    defer { session?.end(); session = nil; builder = nil; ending = false; finalizing = false; checkpoint() }
    guard let builder else { recording?.healthSaveMessage = "Saved measurements locally. Apple Health recording was interrupted."; return }
    do {
      #if os(iOS)
      let type = HKQuantityType(.distanceWalkingRunning)
      let alreadyAdded = builder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
      let missing = max(0, (recording?.meters ?? 0) - alreadyAdded)
      if missing > 0, health.authorizationStatus(for: type) == .sharingAuthorized, let start = recording?.startedAt {
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .meter(), doubleValue: missing), start: start, end: end)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
          builder.add([sample]) { success, error in
            if let error { continuation.resume(throwing: error) }
            else if success { continuation.resume() }
            else { continuation.resume(throwing: RecorderError.message(L10n.text("Distance could not be added to Apple Health."))) }
          }
        }
      }
      #endif
      let routeBuilder = builder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
      var routeFailed = false
      if let routeBuilder, let recording, !recording.route.isEmpty {
        let locations = recording.route.map { CLLocation(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), altitude: $0.altitude, horizontalAccuracy: $0.accuracy, verticalAccuracy: -1, timestamp: $0.timestamp) }
        do { try await routeBuilder.insertRouteData(locations) } catch { routeFailed = true }
      }
      try await collect(builder, end: end)
      #if os(watchOS)
      if let meters = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()) {
        recording?.updateFinalDistance(meters)
      }
      #endif
      let heart = builder.statistics(for: HKQuantityType(.heartRate))
      let unit = HKUnit.count().unitDivided(by: .minute())
      recording?.averageHeartRate = heart?.averageQuantity()?.doubleValue(for: unit)
      recording?.maximumHeartRate = heart?.maximumQuantity()?.doubleValue(for: unit)
      guard recording?.canSave == true else {
        builder.discardWorkout()
        recording?.healthSaveMessage = "No measurable run was saved to Apple Health."
        return
      }
      let workout = try await builder.finishWorkout()
      recording?.healthWorkoutID = workout?.uuid
      if let workout, let routeBuilder, !routeFailed, recording?.route.isEmpty == false {
        do { _ = try await routeBuilder.finishRoute(with: workout, metadata: nil) }
        catch { routeFailed = true }
      }
      if routeFailed { recording?.recoveryMessage = "The route is retained in hybrd, but could not be saved to Apple Health." }
      recording?.healthSaveMessage = workout == nil ? "Saved locally; Apple Health did not return a workout." : "Saved to Apple Health"
      #if os(iOS)
      if workout != nil, health.authorizationStatus(for: HKQuantityType(.distanceWalkingRunning)) != .sharingAuthorized {
        recording?.healthSaveMessage = "Workout saved to Apple Health. Distance stays in hybrd because distance sharing is off."
      }
      #endif
    } catch {
      recording?.markHealthSaveFailure()
      errorMessage = error.localizedDescription
    }
  }
  func discard() {
    guard !ending, recording != nil else { return }
    stopSensors(); builder?.discardWorkout(); session?.end(); session = nil; builder = nil
    do { try RunArchive.removeCheckpoint(recording!.id); recording = nil }
    catch { errorMessage = L10n.text("The saved checkpoint could not be removed. Please try again.") }
  }
  @discardableResult func clearAfterSaving() -> Bool {
    guard recording?.isFinished == true, !ending else { return false }
    do { try RunArchive.removeCheckpoint(recording!.id); recording = nil; return true }
    catch { errorMessage = L10n.text("Your run was saved, but its checkpoint could not be cleared. Retry Done."); return false }
  }
  @discardableResult private func checkpoint() -> Bool {
    guard var value = recording else { return true }
    value.checkpointAt = Date(); recording = value
    do { _ = try RunArchive.checkpoint(value, points: Array(value.route.dropFirst(routeCheckpointCount))); routeCheckpointCount = value.route.count; lastCheckpoint = Date(); return true }
    catch { errorMessage = L10n.text("Couldn’t save the run checkpoint. Keep this session open and free up device storage."); return false }
  }
  private func feedback() {
    cue += 1
    #if os(watchOS)
    WKInterfaceDevice.current().play(.notification)
    #endif
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    Task { @MainActor in self.accept(locations) }
  }
  private func accept(_ locations: [CLLocation]) {
    guard var value = recording, !value.isPaused, !value.isFinished, !ending else { return }
    for fix in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
      let point = RunLocation(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
        altitude: fix.altitude, accuracy: fix.horizontalAccuracy, timestamp: fix.timestamp)
      if let previous = gpsFilter.previous, (0...25).contains(point.accuracy),
        abs(point.timestamp.timeIntervalSinceNow) <= 12, point.timestamp > previous.timestamp,
        RunGPSFilter.distance(previous, point) < 3 {
        lastLocationAt = point.timestamp; gpsMessage = L10n.text("GPS connected"); currentPace = nil; speeds = []
        continue
      }
      guard let accepted = gpsFilter.accept(point, now: Date(), after: value.runningSince ?? value.startedAt) else { continue }
      #if os(iOS)
      let before = value.kilometerMark
      value.updateDistance(value.meters + accepted.meters, at: value.seconds(at: fix.timestamp))
      value.observeExecution(at: fix.timestamp)
      if value.kilometerMark > before { feedback() }
      #endif
      let speed = fix.speed >= 0 ? fix.speed : accepted.seconds > 0 ? accepted.meters / accepted.seconds : 0
      if !accepted.point.startsSegment, (0.5...12).contains(speed) {
        speeds.append(speed); speeds = Array(speeds.suffix(5))
        let pace = 1_000 / (speeds.reduce(0, +) / Double(speeds.count))
        currentPace = pace
        value.rememberPace(pace, at: fix.timestamp)
      } else { currentPace = nil; speeds = [] }
      if value.route.count < 30_000, accepted.point.startsSegment || value.route.last.map({ fix.timestamp.timeIntervalSince($0.timestamp) >= 3 }) ?? true { value.route.append(accepted.point) }
      if value.route.count == 30_000 { value.recoveryMessage = "The route reached its point limit. Distance and time continued recording." }
      lastLocationAt = fix.timestamp; gpsMessage = L10n.text("GPS connected")
    }
    recording = value
  }
  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in self.gpsMessage = L10n.text("GPS interrupted"); self.gpsFilter.reset(); self.currentPace = nil }
  }
  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
    Task { @MainActor in
      guard self.session === workoutSession else { return }
      switch toState {
      case .paused: self.recording?.pause(at: date); self.stopSensors(); self.checkpoint()
      case .running: self.recording?.resume(at: date); self.startSensors(); self.checkpoint()
      case .stopped: await self.finishCollection(at: date)
      case .ended:
        if self.recording?.isFinished == false { await self.finishCollection(at: date) }
      default: break
      }
    }
  }
  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    Task { @MainActor in
      guard self.session === workoutSession else { return }
      self.errorMessage = L10n.text("Workout interrupted: ") + error.localizedDescription
      self.recording?.recoveryMessage = "Recording was interrupted. Review the measurements captured so far."
      await self.finishCollection(at: Date())
    }
  }
  nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
  nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
    Task { @MainActor in
      guard self.builder === workoutBuilder, var value = self.recording, !value.isFinished else { return }
      let heart = workoutBuilder.statistics(for: HKQuantityType(.heartRate))
      let unit = HKUnit.count().unitDivided(by: .minute())
      if let bpm = heart?.mostRecentQuantity()?.doubleValue(for: unit), (20...250).contains(bpm) {
        value.heartRate = bpm; value.heartRateAt = heart?.mostRecentQuantityDateInterval()?.end
        value.averageHeartRate = heart?.averageQuantity()?.doubleValue(for: unit)
        value.maximumHeartRate = heart?.maximumQuantity()?.doubleValue(for: unit)
      }
      #if os(watchOS)
      if let meters = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()), !value.isPaused {
        let before = value.kilometerMark
        value.updateDistance(meters, at: value.seconds())
        value.observeExecution(at: Date())
        if value.kilometerMark > before { self.feedback() }
      }
      #endif
      self.recording = value
    }
  }
}

private enum RecorderError: LocalizedError {
  case message(String)
  var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
