import Foundation
import Observation
import UIKit
import CryptoKit

@MainActor @Observable final class BackendAppController {
  var session = BackendSession()
  private(set) var coach: AgentRunStore?
  private(set) var replica: BackendReplica?
  private(set) var remote: RemoteOnboardingStore?
  private(set) var catalog: BackendWire.ExerciseCatalog?
  private(set) var policy: BackendWire.TrainingPolicy?
  private(set) var bootstrap: BackendWire.Bootstrap?
  private(set) var onboarding: OnboardingStore?
  private(set) var connected = false
  private(set) var launching = true
  private(set) var connectedUserID: String?
  private(set) var connectedEmail: String?
  var canAuthenticateDuringRun: Bool { RunRecorder.shared.recording == nil || !connected || connectedUserID != nil }
  var lockedRecordingEmail: String? { RunRecorder.shared.recording == nil ? nil : connectedEmail }
  private(set) var onboardingPresented = false
  private(set) var onboardingConflict = false
  private(set) var busy = false
  private(set) var lastSynced: Date?
  private(set) var progress: BackendWire.ProgressSummary?
  var error: String?
  var showAccount = false
  var showAuthentication = false
  @ObservationIgnored private var training: TrainingStore?
  @ObservationIgnored private var baseDraft: BackendWire.OnboardingDraft?
  @ObservationIgnored private var syncTask: Task<Void, Never>?
  @ObservationIgnored private var progressResponses: [String: BackendSession.ProgressResponse] = [:]
  @ObservationIgnored private var launchAttempted = false
  @ObservationIgnored private var accountGeneration = UUID()
  var needsOnboarding: Bool { connected && onboardingPresented }
  var hasExistingSetup: Bool { replica?.records.contains { if case .planningContextSnapshot(let v) = $0 { return v.payload != nil }; return false } ?? false }
  var pendingCount: Int { replica?.snapshot.outbox.count ?? 0 }
  var conflicts: [BackendWire.MutationResult] { replica?.snapshot.outcomes ?? [] }
  init() {
    #if DEBUG
    if session.environment == nil { try? session.configure(BackendEnvironment(origin: "http://localhost:3000")) }
    #endif
  }
  func launch(training: TrainingStore) async {
    self.training = training
    guard !launchAttempted else { return }; launchAttempted = true
    defer { launching = false; if !session.authenticated { training.disconnectBackend() } }
    do { try await session.restore(); if session.authenticated { await connect(training: training) } }
    catch {
      if error is URLError && session.authenticated { await connect(training: training) }
      else { self.error = BackendErrorMessage.text(error) }
    }
  }
  func connect(training: TrainingStore) async {
    guard !busy, session.authenticated, let environment = session.environment else { return }
    self.training = training; busy = true; defer { busy = false }
    let generation = accountGeneration
    do {
      var offline = false
      let cacheURL = try manifestURL(environment: environment, user: session.credential!.user.id)
      let cached = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: cacheURL))
      let bootstrap: BackendWire.Bootstrap
      do { bootstrap = try await session.domain("bootstrap") }
      catch let error as URLError {
        guard let cached, cached.userID == session.credential?.user.id else { throw error }
        bootstrap = cached.bootstrap; offline = true
      }
      let scope = try BackendAccountScope(origin: environment.origin, athleteID: bootstrap.athlete.id, apiVersion: environment.apiVersion)
      let user = session.credential!.user.id
      let assertAccount = { [weak self] in
        guard let self, self.accountGeneration == generation, self.session.authenticated,
          self.session.environment == environment, self.session.credential?.user.id == user else { throw BackendContractError.accountChanged }
      }
      let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent("hybrd-backend").appendingPathComponent(environment.storageID)
      let replica = try BackendReplica(directory: directory.appendingPathComponent("replica"), scope: scope, assertAccount: assertAccount)
      let api = OnboardingAPIClient(scope: scope, credentials: { [weak self] in
        try assertAccount(); return .init(scope: scope, token: self!.session.credential!.token)
      }, rotateToken: { [weak self] _, token in try assertAccount(); try self?.session.rotate(token) }, unauthorized: { [weak self] in try? self?.session.clear() })
      let remote = try RemoteOnboardingStore(api: api, directory: directory.appendingPathComponent("onboarding"))
      self.replica = replica; self.remote = remote; self.bootstrap = bootstrap
      if !offline { try await registerDevice() }
      let catalog: BackendWire.ExerciseCatalog = try await offline ? cached!.catalog : session.domain("catalog")
      let policy: BackendWire.TrainingPolicy = try await offline ? cached!.policy : session.domain("config/training-policy")
      try assertAccount()
      guard policy.schemaVersion == 1,
        policy.minimumAppVersion.map({ $0.compare(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0", options: .numeric) != .orderedDescending }) ?? true else { throw BackendContractError.unexpectedValue }
      self.catalog = catalog; self.policy = policy
      if !offline { try await replica.sync(session: session); try await remote.restore() }
      guard remote.state != nil else { throw BackendContractError.restoreRequired }
      try assertAccount()
      let key = "hybrd.connected.onboarding." + environment.storageID + "." + scope.athleteID.uuidString
      let draftStore = OnboardingStore(key: key)
      let prior = UserDefaults.standard.data(forKey: key + ".ack").flatMap { try? JSONDecoder().decode(OnboardingDraft.self, from: $0) }
      let localChanged = draftStore.started && prior != nil && draftStore.draft != prior
      onboardingConflict = localChanged && UserDefaults.standard.string(forKey: key + ".revision") != remote.state?.draftRevision?.rawValue
      baseDraft = remote.state?.draft
      if let draft = remote.state?.draft, !localChanged {
        draftStore.restoreConnected(try ConnectedDraftMapping.native(draft, catalog: catalog), step: ConnectedDraftMapping.step(remote.state?.step))
      } else if !draftStore.started {
        var draft = OnboardingDraft(); draft.name = session.credential?.user.name ?? ""
        draftStore.restoreConnected(draft, step: .identity)
      }
      onboarding = draftStore
      if !localChanged { try saveDraftCheckpoint() }
      onboardingPresented = remote.state?.status != .completed && !hasExistingSetup
      if let run = RunRecorder.shared.recording, !connected {
        let belongsToAccount = replica.records.contains { change in
          guard case .planVersion(let value) = change, let plan = value.payload else { return false }
          return plan.workouts.contains { workout in
            switch workout { case .running(let w): return w.id == run.workout.id; case .strength: return false }
          }
        }
        guard belongsToAccount else { throw BackendContractError.accountChanged }
      }
      try hydrate()
      error = offline ? L10n.text("Offline. Showing your saved account data.") : nil; lastSynced = offline ? cached?.savedAt : Date()
      if !offline { try saveManifest(Manifest(userID: user, bootstrap: bootstrap, catalog: catalog, policy: policy, savedAt: Date()), to: cacheURL) }
      training.connectBackend(athleteID: scope.athleteID, exerciseNames: Set(catalog.exercises.filter(\.active).map { $0.name.lowercased() } + catalog.aliases.map { $0.alias.lowercased() })) { [weak self] old, next in
        guard let self else { throw BackendContractError.accountChanged }; try assertAccount()
        let mutations = try BackendTrainingWrites.mutations(from: old, to: next, replica: replica, catalog: catalog, policy: policy)
        if mutations.isEmpty { try replica.saveLocal(next) }
        else { try replica.enqueue(mutations, local: next); self.scheduleSync() }
      }
      connectedUserID = user; connectedEmail = session.credential?.user.email
      connected = true; showAuthentication = false
      coach?.suspend()
      coach = try AgentRunStore(directory: directory.appendingPathComponent("coach"), scope: scope,
        deviceID: replica.snapshot.deviceID, session: session, assertAccount: assertAccount, beforeSend: { [weak self] in
          guard let self else { throw BackendContractError.accountChanged }
          try assertAccount(); try await self.prepareCoach()
        })
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  func verifyEmail(_ code: String, training: TrainingStore) async throws {
    guard canAuthenticateDuringRun else { throw BackendContractError.accountChanged }
    let requiredUser = RunRecorder.shared.recording == nil ? nil : connectedUserID
    try await session.verify(code)
    if let requiredUser, session.credential?.user.id != requiredUser {
      try session.clear(); throw BackendContractError.accountChanged
    }
    await connect(training: training)
  }
  func sessionEnded() {
    coach?.suspend()
    if RunRecorder.shared.recording != nil, connected {
      // Keep the current account and recorder visible. Reauthentication must use this same user.
      error = L10n.text("Your session expired. Sign in again to continue.")
    } else { disconnect() }
  }
  private func registerDevice() async throws {
    guard let replica else { throw BackendContractError.restoreRequired }
    let registration = BackendWire.DeviceRegistration(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
      osVersion: UIDevice.current.systemVersion, pushEnvironment: .sandbox, pushEnabled: false)
    let _: BackendWire.RegisteredDevice = try await session.domain("devices/" + replica.snapshot.deviceID.uuidString, method: "PUT", body: OnboardingAPIClient.encode(registration))
  }
  func refresh() async {
    guard connected, !busy, let replica else { return }
    busy = true; defer { busy = false }
    do {
      do { try await replica.sync(session: session) }
      catch let api as BackendAPIError where api.code == "DEVICE_UNAVAILABLE" { try await registerDevice(); try await replica.sync(session: session) }
      try hydrate(); error = nil; lastSynced = Date()
      if !conflicts.isEmpty { error = L10n.text("Some changes need review. Open Account & sync for details.") }
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  var cloudAIConsent: Bool {
    replica?.records.compactMap { change -> Bool? in
      if case .athlete(let value) = change { return value.payload?.cloudAiConsent }; return nil
    }.first ?? bootstrap?.athlete.cloudAiConsent ?? false
  }
  private func prepareCoach() async throws {
    guard !busy, let replica else { throw BackendContractError.requestInFlight }
    busy = true; defer { busy = false }
    try await replica.sync(session: session)
    guard replica.snapshot.outbox.isEmpty, replica.snapshot.outcomes.isEmpty else { throw BackendContractError.pendingRequestNeedsReview }
    try hydrate()
    guard cloudAIConsent else { throw BackendAPIError(status: 403, code: "AI_CONSENT_REQUIRED") }
  }
  func setCloudAIConsent(_ enabled: Bool) async {
    guard !busy, let replica, let training else { return }
    busy = true; defer { busy = false }
    do {
      coach?.suspend()
      try await replica.sync(session: session)
      guard replica.snapshot.outbox.isEmpty, replica.snapshot.outcomes.isEmpty else { throw BackendContractError.pendingRequestNeedsReview }
      guard let source = replica.records.compactMap({ change -> BackendWire.AthleteRecord? in
        if case .athlete(let value) = change { return value.payload }; return nil
      }).first else { throw BackendContractError.restoreRequired }
      var input: BackendWire.AthleteProfileInput = try BackendTrainingMapping.convert(source)
      input.cloudAiConsent = enabled
      try replica.enqueue([try BackendMutation(.athlete, id: source.id, operation: .update, revision: source.revision, payload: input)], local: training.state)
      try await replica.sync(session: session)
      guard replica.snapshot.outbox.isEmpty else { throw BackendContractError.pendingRequestNeedsReview }
      try hydrate(); error = nil
      await coach?.refresh()
      if enabled { coach?.resume() }
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  func fetchProgress(days: Int) async {
    guard connected else { return }
    do {
      let timezone = bootstrap?.athlete.timezone ?? TimeZone.current.identifier
      let key = String(days) + "|" + timezone
      let response = try await session.progressSummary(days: days, timezone: timezone, previous: progressResponses[key])
      progressResponses[key] = response; progress = response.value
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  private func hydrate() throws {
    guard let replica, let catalog, let training else { throw BackendContractError.restoreRequired }
    if !replica.snapshot.outbox.isEmpty, let pending = replica.snapshot.local { training.restoreBackend(pending); return }
    let state = try BackendTrainingMapping.state(records: replica.records, athleteID: replica.snapshot.scope.athleteID,
      name: session.credential?.user.name ?? "", catalog: catalog, retaining: replica.snapshot.local)
    try replica.saveLocal(state); training.restoreBackend(state)
  }
  func saveOnboarding(complete: Bool) async throws {
    guard let remote, let catalog, let onboarding, let replica, let policy else { throw BackendContractError.restoreRequired }
    guard onboarding.draft.validation(for: complete ? .summary : onboarding.step) == nil else { throw BackendContractError.invalidDraft }
    if onboardingConflict { throw BackendContractError.pendingRequestNeedsReview }
    if remote.hasPendingRequest { throw BackendContractError.pendingRequestNeedsReview }
    let wire = try ConnectedDraftMapping.wire(onboarding.draft, original: baseDraft, catalog: catalog)
    try await remote.saveReviewedDraft(wire, step: OnboardingDraftAdapter.step(onboarding.step))
    baseDraft = remote.state?.draft
    try saveDraftCheckpoint()
    if complete {
      try await remote.completeReviewedDraft(deviceID: replica.snapshot.deviceID, catalogVersion: catalog.version, policyID: policy.id)
      try await replica.sync(session: session); try hydrate()
    }
  }
  func retryOnboarding() async {
    guard let remote else { return }
    do {
      try await remote.retryPending(); baseDraft = remote.state?.draft
      if remote.state?.status == .completed { onboardingPresented = false; await refresh() }
      error = nil
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  func fetchOnboardingForReview() async {
    do { try await remote?.restore() } catch { self.error = BackendErrorMessage.text(error) }
  }
  func useServerOnboarding() async {
    guard let remote, let onboarding, let catalog else { return }
    do {
      try await remote.restore()
      // The user explicitly chose the server's answers after viewing the conflict.
      try remote.discardPendingAfterReview()
      baseDraft = remote.state?.draft
      if let d = baseDraft { onboarding.restoreConnected(try ConnectedDraftMapping.native(d, catalog: catalog), step: ConnectedDraftMapping.step(remote.state?.step)) }
      onboardingConflict = false; try saveDraftCheckpoint()
      error = nil
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  func useServerTraining() async {
    do { try replica?.discardRejectedChanges(); await refresh() }
    catch { self.error = BackendErrorMessage.text(error) }
  }
  func finishJourney() { onboardingPresented = false }
  private func saveDraftCheckpoint() throws {
    guard let environment = session.environment, let replica, let onboarding else { return }
    let key = "hybrd.connected.onboarding." + environment.storageID + "." + replica.snapshot.scope.athleteID.uuidString
    UserDefaults.standard.set(try JSONEncoder().encode(onboarding.draft), forKey: key + ".ack")
    UserDefaults.standard.set(remote?.state?.draftRevision?.rawValue, forKey: key + ".revision")
  }
  private struct Manifest: Codable {
    var userID: String; var bootstrap: BackendWire.Bootstrap; var catalog: BackendWire.ExerciseCatalog; var policy: BackendWire.TrainingPolicy; var savedAt: Date
  }
  private func manifestURL(environment: BackendEnvironment, user: String) throws -> URL {
    let key = SHA256.hash(data: Data(user.utf8)).map { String(format: "%02x", $0) }.joined()
    return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("hybrd-backend").appendingPathComponent(environment.storageID).appendingPathComponent("account-" + key + ".json")
  }
  private func saveManifest(_ manifest: Manifest, to url: URL) throws {
    try OnboardingAPIClient.encode(manifest).write(to: url, options: [.atomic, .completeFileProtection])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    var destination = url; var values = URLResourceValues(); values.isExcludedFromBackup = true; try destination.setResourceValues(values)
  }
  private func scheduleSync() {
    syncTask?.cancel(); syncTask = Task { [weak self] in await Task.yield(); await self?.refresh() }
  }
  func signOut(localOnly: Bool = false) async {
    guard !busy, RunRecorder.shared.recording == nil else { error = L10n.text("Finish your active workout before switching accounts."); return }
    do {
      syncTask?.cancel()
      if localOnly { try session.clear() } else { try await session.signOut() }
      disconnect()
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  func disconnect() {
    coach?.suspend(); coach = nil
    accountGeneration = UUID(); syncTask?.cancel(); connected = false
    connectedUserID = nil; connectedEmail = nil; progressResponses = [:]
    replica = nil; remote = nil; catalog = nil; policy = nil; bootstrap = nil; progress = nil; onboarding = nil
    training?.disconnectBackend(); showAccount = false; onboardingPresented = false; onboardingConflict = false; lastSynced = nil
  }
}
