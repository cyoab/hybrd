import Foundation

@MainActor enum BackendLiveChecks {
  static func run() async throws {
    guard let origin = ProcessInfo.processInfo.environment["HYBRD_BACKEND_TEST_URL"] else { return }
    let suite = "hybrd.live-tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var saved: BackendSession.Credential?
    let session = BackendSession(defaults: defaults, load: { _ in saved }, save: { credential, _ in saved = credential })
    let environment = try BackendEnvironment(origin: origin)
    try session.configure(environment); try await session.discover()
    precondition(session.methods?.emailOtp == true)
    let email = "native-" + UUID().uuidString.lowercased() + "@example.test"
    try await session.sendCode(to: email)
    struct Inbox: Decodable { var otp: String }
    var inboxURL = URLComponents(string: origin + "/test/inbox")!; inboxURL.queryItems = [.init(name: "email", value: email)]
    let (inboxData, _) = try await URLSession.shared.data(from: inboxURL.url!)
    try await session.verify(JSONDecoder().decode(Inbox.self, from: inboxData).otp)
    precondition(session.authenticated && saved != nil)
    print("Native live check: email verified")
    let bootstrap: BackendWire.Bootstrap = try await session.domain("bootstrap")
    let scope = try BackendAccountScope(origin: environment.origin, athleteID: bootstrap.athlete.id)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let assertAccount = { guard session.authenticated else { throw BackendContractError.accountChanged } }
    let replica = try BackendReplica(directory: directory.appendingPathComponent("replica"), scope: scope, assertAccount: assertAccount)
    let registration = BackendWire.DeviceRegistration(appVersion: "1.0", pushEnvironment: .sandbox, pushEnabled: false)
    let _: BackendWire.RegisteredDevice = try await session.domain("devices/" + replica.snapshot.deviceID.uuidString, method: "PUT", body: OnboardingAPIClient.encode(registration))
    let catalog: BackendWire.ExerciseCatalog = try await session.domain("catalog")
    let policy: BackendWire.TrainingPolicy = try await session.domain("config/training-policy")
    try await replica.sync(session: session)
    print("Native live check: bootstrap, catalog, policy and initial sync restored")
    let api = OnboardingAPIClient(scope: scope, credentials: { .init(scope: scope, token: session.credential!.token) }, rotateToken: { _, token in try session.rotate(token) })
    let remote = try RemoteOnboardingStore(api: api, directory: directory.appendingPathComponent("onboarding"))
    try await remote.restore(); precondition(remote.state?.status == .notStarted)
    var draft = OnboardingDraft(); draft.name = "Native test"; draft.runningGoal = .fiveK; draft.strengthGoal = .build; draft.priority = .balanced
    draft.runningLevel = .beginner; draft.strengthLevel = .intermediate; draft.weeklyDistance = "24"; draft.currentLiftDays = 2.5
    draft.availableDays = [2,3,4,5,6,7]; draft.strengthDays = 2; draft.sessionMinutes = 45
    draft.equipment = [.dumbbells, .barbell, .bench, .latPulldown]; draft.equipmentConfirmed = true; draft.readiness = .ready
    let wire = try ConnectedDraftMapping.wire(draft, original: nil, catalog: catalog)
    try await remote.saveReviewedDraft(wire, step: .review)
    try await remote.completeReviewedDraft(deviceID: replica.snapshot.deviceID, catalogVersion: catalog.version, policyID: policy.id)
    precondition(remote.state?.status == .completed)
    print("Native live check: onboarding completed")
    try await replica.sync(session: session)
    var native = try BackendTrainingMapping.state(records: replica.records, athleteID: scope.athleteID, name: "", catalog: catalog, retaining: nil)
    precondition(native.profile.name == "Native test" && native.results.isEmpty && native.plans.last!.workouts.isEmpty)
    var edited = native; edited.profile.name = "Native reviewed"; edited.profile.units = TrainingUnits(weight: .pounds, distance: .miles)
    edited.profile.athlete?.heartRateZones = PersonalHeartRateZones(zone2: 120, zone3: 140, zone4: 160, zone5: 180)
    let edits = try BackendTrainingWrites.mutations(from: native, to: edited, replica: replica, catalog: catalog, policy: policy)
    try replica.enqueue(edits, local: edited); try await replica.sync(session: session)
    try checkOutbox(replica, phase: "profile")
    native = try BackendTrainingMapping.state(records: replica.records, athleteID: scope.athleteID, name: "", catalog: catalog, retaining: edited)
    precondition(native.profile.name == "Native reviewed" && native.profile.trainingUnits.distance == .miles)
    var withPlan = native
    var plan = TrainingEngine.makePlan(profile: native.profile, basePlanID: native.plans.last!.id, availableExerciseNames: Set(catalog.exercises.filter(\.active).map { $0.name.lowercased() } + catalog.aliases.map { $0.alias.lowercased() }))
    if let i = plan.workouts.firstIndex(where: { $0.kind == .run }) {
      plan.workouts[i].segments = [RunSegment(title: "Work", seconds: 120, cue: "Controlled", phase: .work, repetitions: 3, heartRateZone: .four), RunSegment(title: "Recovery", seconds: 60, cue: "Easy", phase: .recovery, repetitions: 3, heartRateZone: .two)]
    }
    withPlan.plans.append(plan)
    let planWrites = try BackendTrainingWrites.mutations(from: native, to: withPlan, replica: replica, catalog: catalog, policy: policy)
    try replica.enqueue(planWrites, local: withPlan); try await replica.sync(session: session)
    try checkOutbox(replica, phase: "plan")
    native = try BackendTrainingMapping.state(records: replica.records, athleteID: scope.athleteID, name: "", catalog: catalog, retaining: withPlan)
    precondition(native.plans.last?.id == plan.id)
    let restoredPlan = try BackendTrainingMapping.state(records: replica.records, athleteID: scope.athleteID, name: "", catalog: catalog, retaining: nil).plans.last!
    let originalRun = plan.workouts.first { $0.kind == .run }!, restoredRun = restoredPlan.workouts.first { $0.logicalID == originalRun.logicalID }!
    precondition(RunTimeline(segments: originalRun.segments).steps.map { $0.segment.phase } == RunTimeline(segments: restoredRun.segments).steps.map { $0.segment.phase })
    precondition(restoredRun.segments.first?.heartRateZone == .four)
    let run = plan.workouts.first { $0.kind == .run }!, lift = plan.workouts.first { $0.kind == .strength }!
    var withResults = native
    let end = Date().addingTimeInterval(-1), start = end.addingTimeInterval(-2100)
    var recording = RunRecording(workout: run, source: .phone, startedAt: start, checkpointAt: end)
    recording.recordedTimeZoneID = "America/Monterrey"
    recording.endedAt = end; recording.elapsed = 1800; recording.meters = 5000
    recording.averageHeartRate = 151.4; recording.maximumHeartRate = 176.2
    recording.laps = [.init(kind: .kilometer, number: 1, meters: 1000, seconds: 360), .init(kind: .manual, number: 1, meters: 5000, seconds: 1800)]
    recording.route = [.init(latitude: 25.68, longitude: -100.3, altitude: 540, accuracy: 5, timestamp: start)]
    withResults.results.append(recording.result())
    let e = lift.exercises[0]
    withResults.results.append(WorkoutResult(plannedWorkoutID: lift.id, logicalWorkoutID: lift.logicalID, kind: .strength, status: .partial, durationSeconds: 1200, effort: 5, notes: "", sets: [LoggedSet(prescriptionID: e.sets[0].id, exerciseName: e.name, reps: 6, kilograms: 20, isComplete: true, rir: 3)]))
    // Unknown timing in a manually entered log must not be fabricated from its log timestamp.
    let entered = WorkoutResult(plannedWorkoutID: run.id, logicalWorkoutID: UUID(), kind: .run, status: .completed,
      durationSeconds: 1200, distanceMeters: 3000, effort: 0, notes: "", sets: [])
    let enteredMutation = try BackendTrainingMapping.resultMutation(entered, state: withResults, catalog: catalog, knownPlans: Set(plan.workouts.map(\.id)))
    let enteredWire = try JSONDecoder().decode(BackendWire.WorkoutResultInputRunning.self, from: OnboardingAPIClient.encode(enteredMutation.payload))
    precondition(enteredWire.dateBasis == .loggedDate && enteredWire.startedAt == nil && enteredWire.endedAt == nil && enteredWire.plannedWorkoutId == nil)
    precondition(enteredWire.durationS == 1200 && enteredWire.run?.movingDurationS == nil)
    let resultWrites = try BackendTrainingWrites.mutations(from: native, to: withResults, replica: replica, catalog: catalog, policy: policy)
    try replica.enqueue(resultWrites, local: withResults); try await replica.sync(session: session)
    try checkOutbox(replica, phase: "results")
    let canonicalRun = replica.records.compactMap { change -> BackendWire.WorkoutResultRecordRunning? in
      guard case .workoutResult(let v) = change, case .running(let run)? = v.payload else { return nil }; return run
    }.first!
    precondition(canonicalRun.durationS == 2100 && canonicalRun.run?.durationS == 2100 && canonicalRun.run?.movingDurationS == nil)
    precondition(canonicalRun.run?.avgHrBpm == 151 && (canonicalRun.run?.segments?.isEmpty ?? true))
    precondition(canonicalRun.dateBasis == .performedDate && canonicalRun.timezone == "America/Monterrey")
    let canonicalLift = replica.records.compactMap { change -> BackendWire.WorkoutResultRecordStrength? in
      guard case .workoutResult(let v) = change, case .strength(let lift)? = v.payload else { return nil }; return lift
    }.first!
    precondition(canonicalLift.durationS == nil && canonicalLift.startedAt == nil && canonicalLift.endedAt == nil && canonicalLift.dateBasis == .loggedDate)
    let hydrated = try BackendTrainingMapping.state(records: replica.records, athleteID: scope.athleteID, name: "", catalog: catalog, retaining: withResults)
    precondition(hydrated.results.first { $0.id == recording.id }?.run == recording)
    precondition(hydrated.results.first { $0.id == recording.id }?.durationSeconds == 2100)
    var moved = withResults
    let upcoming = plan.workouts.first { $0.logicalID != run.logicalID && $0.logicalID != lift.logicalID }!
    moved.plans.append(TrainingEngine.moving(upcoming, to: Calendar.current.date(byAdding: .day, value: 1, to: upcoming.date)!, in: plan))
    let moves = try BackendTrainingWrites.mutations(from: withResults, to: moved, replica: replica, catalog: catalog, policy: policy)
    try replica.enqueue(moves, local: moved); try await replica.sync(session: session)
    try checkOutbox(replica, phase: "move with completed history")
    let firstProgress = try await session.progressSummary(days: 28, timezone: "America/Monterrey", previous: nil)
    precondition(firstProgress.etag != nil)
    let cachedProgress = try await session.progressSummary(days: 28, timezone: "America/Monterrey", previous: firstProgress)
    precondition(cachedProgress.value == firstProgress.value)
    let progress = cachedProgress.value
    precondition(progress.totals.lifetime.sessions == 2 && progress.totals.lifetime.runMeters == 5000 && progress.totals.lifetime.strengthSets == 1)
    let restored = try BackendReplica(directory: directory.appendingPathComponent("replica"), scope: scope, assertAccount: assertAccount)
    precondition(restored.snapshot.cursor == replica.snapshot.cursor)
    try await session.signOut(); precondition(saved == nil && !session.authenticated)
    var cleanup = URLRequest(url: URL(string: origin + "/test/cleanup")!); cleanup.httpMethod = "POST"
    cleanup.setValue("application/json", forHTTPHeaderField: "Content-Type"); cleanup.httpBody = try JSONEncoder().encode(["email": email])
    let (_, cleanupResponse) = try await URLSession.shared.data(for: cleanup)
    precondition((cleanupResponse as? HTTPURLResponse)?.statusCode == 200)
    print("PASS: live Swift email OTP → bootstrap → device → onboarding → profile → plan activation → run/lift upload → canonical progress → restart → sign-out")
  }
  private static func checkOutbox(_ replica: BackendReplica, phase: String) throws {
    if !replica.snapshot.outbox.isEmpty { throw LiveFailure(phase: phase, codes: replica.snapshot.outcomes.compactMap { $0.error?.code }) }
  }
  struct LiveFailure: Error { var phase: String; var codes: [String] }
}
