import Foundation

enum BackendOnboardingChecks {
  @MainActor static func run() async throws {
    let example = try Data(contentsOf: URL(fileURLWithPath: "../contracts/examples/onboarding-draft.json"))
    let request = try JSONDecoder().decode(BackendWire.SaveOnboardingDraft.self, from: example)
    let roundTrip = try OnboardingAPIClient.encode(request)
    let original = try JSONSerialization.jsonObject(with: example) as! NSDictionary
    check(original.isEqual(to: try JSONSerialization.jsonObject(with: roundTrip) as! [AnyHashable: Any]), "Exact wire names, explicit nulls and enums must match the server fixture")
    var precise = request.draft
    precise.currentStrengthSessionsPerWeek = 2.5
    precise.details.heartRateZones = try JSONDecoder().decode(BackendWire.ReviewedHeartRateZones.self, from: Data(#"{"schemaVersion":1,"configuration":"system","ranges":[{"minBpm":0,"maxBpm":136.8},{"minBpm":136.8,"maxBpm":147.6},{"minBpm":147.6,"maxBpm":158.4},{"minBpm":158.4,"maxBpm":169.2},{"minBpm":169.2,"maxBpm":null}]}"#.utf8))
    precise.importDecisions = try JSONDecoder().decode([BackendWire.OnboardingImportDecision].self, from: Data(#"[{"field":"heightCm","source":"healthkit","decision":"accept","batchId":"11111111-1111-4111-8111-111111111111","sourceIds":["sample-1"],"observation":{"measuredAt":"2026-09-01T12:00:00-06:00","fetchedAt":"2026-09-24T12:00:00.123Z","window":null,"coverage":"complete_returned_records","durationBasis":null,"calculationVersion":1}},{"field":"weightKg","source":"strava","decision":"edit","previewId":"22222222-2222-4222-8222-222222222222","previewRevision":"9007199254740993"}]"#.utf8))
    check(try JSONDecoder().decode(BackendWire.OnboardingDraft.self, from: OnboardingAPIClient.encode(precise)) == precise)
    check(try BackendRevision("9007199254740993") > BackendRevision("9007199254740992"))
    for invalid in ["-1", "01", "1.0", "9223372036854775808"] { check((try? BackendRevision(invalid)) == nil) }
    check((try? BackendDay("2026-02-29")) == nil)
    check(try BackendDay("2024-02-29").rawValue == "2024-02-29")
    check(try BackendInstant("2026-09-24T12:00:00.123-06:00").rawValue.hasSuffix("-06:00"))
    for invalid in ["2026-09-24", "2026-09-24T12:00:00"] { check((try? BackendInstant(invalid)) == nil) }
    check((try? JSONDecoder().decode(BackendWire.OnboardingState.self, from: Data(#"{"schemaVersion":2,"status":"not_started","draft":null,"draftRevision":null,"step":null,"completion":null,"reviewIssues":[]}"#.utf8))) == nil)
    let partial = Data(#"{"available":true,"status":"connected","remoteAthleteId":"123","autoPublish":false,"scopes":["read"],"history":null,"jobs":[],"onboardingPreview":{"id":"11111111-1111-4111-8111-111111111111","revision":"3","generatedAt":"2026-09-24T12:00:00Z","expiresAt":"2026-10-01T12:00:00Z","profile":{"state":"ready","reason":null,"data":{"preferredName":"Sam","weightKg":null,"measuredAt":null},"source":"strava","fetchedAt":"2026-09-24T12:00:00Z","retryAfterSeconds":null,"coverage":"partial"},"heartRateZones":{"state":"unavailable","reason":"scope_missing","data":null,"source":"strava","fetchedAt":null,"retryAfterSeconds":null,"coverage":"unknown"},"runningHistory":{"state":"pending","reason":"rate_limited","data":null,"source":"strava","fetchedAt":null,"retryAfterSeconds":120,"coverage":"unknown"}}}"#.utf8)
    let strava = try JSONDecoder().decode(BackendWire.StravaConnectionStatus.self, from: partial)
    check(strava.onboardingPreview?.profile.data?.preferredName == "Sam")
    check(strava.onboardingPreview?.heartRateZones.reason == .scopeMissing)
    check(strava.onboardingPreview?.runningHistory.retryAfterSeconds == 120 && strava.history == nil)
    try mappingChecks()
    try await requestChecks(draft: precise)
    try await recoveryChecks(draft: request.draft)
    print("Backend onboarding checks passed: wire fixtures, precise imports, mapping, account isolation and durable retries")
  }

  @MainActor private static func mappingChecks() throws {
    let equipment = GymEquipment.allCases.map { BackendWire.ExerciseCatalogEquipmentItem(id: UUID(), slug: OnboardingDraftAdapter.equipmentSlug($0), name: $0.rawValue) }
    let muscles = MuscleGroup.allCases.map { BackendWire.ExerciseCatalogMuscleGroupsItem(id: UUID(), slug: $0.rawValue, name: $0.rawValue) }
    let catalog = BackendWire.ExerciseCatalog(version: 2, exercises: [], equipment: equipment, muscleGroups: muscles, aliases: [], exerciseMuscles: [], exerciseEquipment: [])
    check(try OnboardingDraftAdapter.equipmentIDs(Set(GymEquipment.allCases), in: catalog).count == 20)
    check(try OnboardingDraftAdapter.muscleIDs(Set(MuscleGroup.allCases), in: catalog).count == 10)
    var incomplete = catalog; incomplete.equipment.removeAll()
    check((try? OnboardingDraftAdapter.equipmentIDs([.ezBar], in: incomplete)) == nil, "No silently dropped equipment")
    var draft = OnboardingDraft()
    draft.name = "Sam"; draft.runningGoal = .halfMarathon; draft.strengthGoal = .muscle; draft.priority = .running
    draft.runningLevel = .new; draft.strengthLevel = .advanced; draft.weeklyDistance = "70"; draft.currentLiftDays = 0
    draft.availableDays = Set(1...7); draft.equipmentConfirmed = true; draft.equipment = Set(GymEquipment.allCases)
    draft.focusMuscles = Set(MuscleGroup.allCases); draft.readiness = .ready; draft.age = "30"
    draft.height = "177.8"; draft.weight = "80"; draft.hasRaceDate = true
    let now = try BackendInstant("2026-09-24T18:00:00Z").date
    draft.raceDate = try BackendInstant("2026-12-01T03:00:00Z").date
    let baseline = BackendWire.OnboardingDraftBaselinePeriod(start: try BackendDay("2026-08-27"), end: try BackendDay("2026-09-24"))
    draft.setDistanceUnit(.miles); draft.setWeightUnit(.pounds); draft.setHeightUnit(.feetAndInches)
    let mapped = try OnboardingDraftAdapter.reviewedManualDraft(draft, catalog: catalog, baseline: baseline,
      timeZone: TimeZone(identifier: "America/Monterrey")!, locale: "es", weekStartsOn: 2, now: now)
    check(mapped.weeklyDistanceM == 70_000 && mapped.details.weightKg == 80 && mapped.details.heightCm == 177.8)
    check(mapped.profile?.distanceUnit == .mi && mapped.profile?.loadUnit == .lb && mapped.details.heightUnit == .ftIn)
    check(mapped.raceDate?.rawValue == "2026-11-30", "Race date uses athlete calendar, not UTC midnight")
    check(mapped.currentStrengthSessionsPerWeek == 0 && mapped.runningLevel == .new && mapped.strengthLevel == .advanced)
    check(mapped.runningGoal == .halfMarathon && mapped.strengthGoal == .hypertrophy && mapped.priority == .runFirst)
    check(mapped.availableDays == Array(1...7) && mapped.profile?.cloudAiConsent == false)
    check(mapped.details.dateOfBirth == nil && mapped.details.age?.asOf.rawValue == "2026-09-24")
  }

  @MainActor private static func requestChecks(draft: BackendWire.OnboardingDraft) async throws {
    let scope = try BackendAccountScope(origin: URL(string: "https://api.example.test")!, athleteID: UUID())
    for url in ["http://example.test", "https://user:secret@example.test", "https://example.test/path", "https://example.test?token=x"] {
      check((try? BackendAccountScope(origin: URL(string: url)!, athleteID: UUID())) == nil)
    }
    var active = scope
    var rotated = ""
    var requests: [URLRequest] = []
    let api = OnboardingAPIClient(scope: scope, credentials: { .init(scope: active, token: "test-session") }, rotateToken: { _, token in rotated = token }) { request in
      requests.append(request)
      if request.url!.path.hasSuffix("connect") {
        check(request.httpBody == Data(#"{"autoPublish":false}"#.utf8))
        return response(request, #"{"authorizationUrl":"https://www.strava.com/oauth/mobile/authorize","state":"opaque-state","expiresInSeconds":600}"#)
      }
      if request.url!.path.hasSuffix("history") { return response(request, #"{"jobId":"11111111-1111-4111-8111-111111111111"}"#, status: 202) }
      check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-session")
      return response(request, #"{"schemaVersion":1,"status":"not_started","draft":null,"draftRevision":null,"step":null,"completion":null,"reviewIssues":[]}"#, headers: ["set-auth-token":"renewed-test-session"])
    }
    _ = try await api.connectStrava(); _ = try await api.refreshStrava(); _ = try await api.getOnboarding()
    check(rotated == "renewed-test-session" && requests.map(\.httpMethod) == ["POST", "POST", "GET"])
    active = try BackendAccountScope(origin: scope.origin, athleteID: UUID())
    do { _ = try await api.getOnboarding(); preconditionFailure("Cross-account send") } catch BackendContractError.accountChanged {}
    check(requests.count == 3)
    let switching = OnboardingAPIClient(scope: scope, credentials: { .init(scope: active, token: "t") }, rotateToken: { _, _ in preconditionFailure("Old account token rotation") }) { req in
      active = try BackendAccountScope(origin: scope.origin, athleteID: UUID())
      return response(req, #"{"schemaVersion":1,"status":"not_started","draft":null,"draftRevision":null,"step":null,"completion":null,"reviewIssues":[]}"#)
    }
    active = scope
    do { _ = try await switching.getOnboarding(); preconditionFailure("Applied a response after account switch") } catch BackendContractError.accountChanged {}
    let http = HTTPURLResponse(url: scope.origin, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After":"120", "X-Request-Id":"safe-id"])!
    let error = BackendAPIError.from(http, data: Data(#"{"error":{"code":"RATE_LIMITED","message":"wait"}}"#.utf8))
    check(error.retryAfterSeconds == 120 && error.requestID == "safe-id" && error.recovery == .retry)
  }

  @MainActor private static func recoveryChecks(draft: BackendWire.OnboardingDraft) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hybrd-onboarding-check-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try BackendAccountScope(origin: URL(string: "https://api.example.test")!, athleteID: UUID())
    var remote = BackendWire.OnboardingState(schemaVersion: .value1, status: .notStarted, reviewIssues: [])
    var writes: [URLRequest] = []
    var loseSaveResponse = true, loseCompleteResponse = true, conflict = false
    let api = OnboardingAPIClient(scope: scope, credentials: { .init(scope: scope, token: "secret-session-not-persisted") }, rotateToken: { _, _ in }) { req in
      if req.httpMethod == "GET" { return (try OnboardingAPIClient.encode(remote), http(req)) }
      writes.append(req)
      let key = req.value(forHTTPHeaderField: "Idempotency-Key")!
      check(UUID(uuidString: key) != nil)
      if req.httpMethod == "PUT" {
        if conflict { return response(req, #"{"error":{"code":"ONBOARDING_REVISION_CONFLICT","message":"review","details":{"fields":["draftRevision"]}}}"#, status: 409) }
        let sent = try JSONDecoder().decode(BackendWire.SaveOnboardingDraft.self, from: req.httpBody!)
        remote = .init(schemaVersion: .value1, status: .draft, draft: sent.draft, draftRevision: try BackendRevision("1"), step: .review, reviewIssues: [])
        if loseSaveResponse { loseSaveResponse = false; throw URLError(.timedOut) }
        return response(req, #"{"draftRevision":"1"}"#)
      }
      let ref = #"{"entityType":"athlete_details","id":"11111111-1111-4111-8111-111111111111","revision":"1"}"#
      let receipt = """
      {"submissionId":"\(key)","choices":{"wantsHealth":false,"wantsStrava":false,"membership":"annual"},"completedAt":"2026-09-24T18:00:00.123Z","draftRevision":"1","catalogVersion":2,"policyVersionId":"22222222-2222-4222-8222-222222222222","athleteDetails":\(ref),"baseline":\(ref),"planningContext":\(ref),"saved":[\(ref)],"latestSequence":"9007199254740993","planning":{"status":"unsupported_baseline","reason":"weekly_distance_outside_planner_range","minimumWeeklyDistanceM":3000,"maximumWeeklyDistanceM":150000}}
      """
      if loseCompleteResponse { loseCompleteResponse = false; throw URLError(.networkConnectionLost) }
      return response(req, receipt)
    }
    var store = try RemoteOnboardingStore(api: api, directory: directory)
    do { try await store.saveReviewedDraft(draft, step: .review); preconditionFailure() } catch BackendContractError.restoreRequired {}
    try await store.restore()
    do { try await store.saveReviewedDraft(draft, step: .review); preconditionFailure() } catch is URLError {}
    check(store.hasPendingRequest && store.pendingDraftForReview?.draft == draft)
    store = try RemoteOnboardingStore(api: api, directory: directory)
    try await store.retryPending()
    check(writes[0].httpBody == writes[1].httpBody && writes[0].value(forHTTPHeaderField: "Idempotency-Key") == writes[1].value(forHTTPHeaderField: "Idempotency-Key"))
    check(!store.hasPendingRequest && store.state?.draftRevision?.rawValue == "1")
    conflict = true
    do { try await store.saveReviewedDraft(draft, step: .review); preconditionFailure() }
    catch let error as BackendAPIError { check(error.recovery == .reviewDraft) }
    check(store.hasPendingRequest)
    do { try await store.saveReviewedDraft(draft, step: .review); preconditionFailure() } catch BackendContractError.pendingRequestNeedsReview {}
    try await store.restore(); try store.discardPendingAfterReview(); conflict = false
    do { try await store.completeReviewedDraft(deviceID: UUID(), catalogVersion: 2, policyID: UUID()); preconditionFailure() } catch is URLError {}
    store = try RemoteOnboardingStore(api: api, directory: directory)
    try await store.retryPending()
    check(writes[writes.count-1].httpBody == writes[writes.count-2].httpBody)
    check(writes[writes.count-1].value(forHTTPHeaderField: "Idempotency-Key") == writes[writes.count-2].value(forHTTPHeaderField: "Idempotency-Key"))
    check(store.state?.status == .completed && store.state?.completion?.planning.status == .unsupportedBaseline && !store.hasPendingRequest)
    let journal = OnboardingRequestJournal(directory: directory, scope: scope)
    let saved = try String(contentsOf: journal.file, encoding: .utf8)
    check(!saved.contains("secret-session-not-persisted"))
    check(try RemoteOnboardingStore(api: api, directory: directory).state?.completion?.latestSequence.rawValue == "9007199254740993")
    let other = try BackendAccountScope(origin: scope.origin, athleteID: UUID())
    check(try OnboardingRequestJournal(directory: directory, scope: other).load().remote == nil)
  }
  private static func check(_ value: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    precondition(value, message, file: file, line: line)
  }
  private static func http(_ req: URLRequest, status: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
  }
  private static func response(_ req: URLRequest, _ json: String, status: Int = 200, headers: [String:String] = [:]) -> (Data, HTTPURLResponse) {
    (Data(json.utf8), http(req, status: status, headers: headers))
  }
}
