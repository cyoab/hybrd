import Foundation
import Observation

/// One durable journal per environment/API/athlete. Request bytes are saved before POST.
@MainActor @Observable final class AgentRunStore {
  struct Entry: Codable, Identifiable {
    var id = UUID() // Idempotency key; never regenerated for a retry.
    var request: BackendWire.AgentRunInput
    var body: Data
    var createdAt = Date()
    var run: BackendWire.AgentRun?
    var cursor = try! BackendRevision("0")
    var cancellationRequested = false
    var rejection: String?
    var pending: Bool { rejection == nil && (run.map { !Self.terminal($0.status) } ?? true) }
    static func terminal(_ status: BackendWire.AgentRunStatus) -> Bool {
      switch status { case .queued, .running: false; default: true }
    }
  }
  struct Snapshot: Codable {
    var version = 1
    var scope: BackendAccountScope
    var threadID: UUID?
    var entries: [Entry] = []
  }
  private(set) var snapshot: Snapshot
  private(set) var capabilities: BackendWire.AgentCapabilities?
  private(set) var memories: [BackendWire.AgentMemory] = []
  private(set) var busy = false
  private(set) var activity: String?
  var error: String?
  @ObservationIgnored private let file: URL
  @ObservationIgnored private let session: BackendSession
  @ObservationIgnored private let deviceID: UUID
  @ObservationIgnored private let assertAccount: () throws -> Void
  @ObservationIgnored private let beforeSend: () async throws -> Void
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var suspendedTask: Task<Void, Never>?
  var currentEntries: [Entry] {
    snapshot.entries.filter { ($0.run?.threadId ?? $0.request.threadId) == snapshot.threadID }
  }
  func selectThread(_ id: UUID?) {
    guard pending == nil else { return }
    do { var next = snapshot; next.threadID = id; try persist(next) }
    catch { self.error = BackendErrorMessage.text(error) }
  }
  var pending: Entry? { snapshot.entries.first(where: \.pending) }
  var available: Bool { capabilities?.enabled == true && capabilities?.configured == true && capabilities?.tasks.chat == true }

  init(directory: URL, scope: BackendAccountScope, deviceID: UUID, session: BackendSession,
       assertAccount: @escaping () throws -> Void, beforeSend: @escaping () async throws -> Void) throws {
    self.session = session; self.deviceID = deviceID; self.assertAccount = assertAccount; self.beforeSend = beforeSend
    file = OnboardingRequestJournal(directory: directory, scope: scope).file
    if FileManager.default.fileExists(atPath: file.path) {
      snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
      guard snapshot.version == 1, snapshot.scope == scope, snapshot.entries.count <= 500 else { throw BackendContractError.invalidResponse }
      for entry in snapshot.entries {
        guard try JSONDecoder().decode(BackendWire.AgentRunInput.self, from: entry.body) == entry.request else { throw BackendContractError.invalidResponse }
      }
    } else { snapshot = Snapshot(scope: scope) }
  }
  func refresh() async {
    do {
      let value: BackendWire.AgentCapabilities = try await session.domain("agent/capabilities")
      try assertAccount(); capabilities = value; error = nil
      // Revalidate historical analyses: a corrected/deleted result invalidates its old interpretation.
      for entry in snapshot.entries.suffix(50) where entry.run?.artifact?.analyzedResult != nil {
        if let id = entry.run?.id {
          let run: BackendWire.AgentRun = try await session.domain("agent/runs/" + id.uuidString.lowercased())
          try update(entry.id, run: run)
        }
      }
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  func start(_ message: String, resultID: UUID? = nil, revision: BackendRevision? = nil) async {
    guard !busy, pending == nil else { return }
    let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty, message.count <= 4_000, available,
      resultID == nil || (capabilities?.tasks.analyzeWorkout == true && revision != nil) else { return }
    busy = true; defer { busy = false }
    do {
      try await beforeSend(); try assertAccount()
      let input = BackendWire.AgentRunInput(schemaVersion: .value1, deviceId: deviceID, threadId: snapshot.threadID,
        task: resultID == nil ? .chat : .analyzeWorkout, message: message, workoutResultId: resultID, expectedWorkoutRevision: revision)
      let entry = Entry(request: input, body: try OnboardingAPIClient.encode(input))
      var next = snapshot
      if next.entries.count >= 500 { next.entries.removeFirst(next.entries.count - 499) }
      next.entries.append(entry); try persist(next)
      error = nil
      resume()
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  func newConversation() {
    selectThread(nil)
  }
  func suspend() { generation = UUID(); suspendedTask = task ?? suspendedTask; task?.cancel(); task = nil; activity = nil }
  func resume() {
    guard task == nil, let entry = pending else { return }
    let expected = generation
    let previous = suspendedTask; suspendedTask = nil
    task = Task { [weak self] in
      await previous?.value
      guard let self, self.generation == expected, !Task.isCancelled else { return }
      defer { if self.generation == expected { self.task = nil; self.activity = nil } }
      do { try await self.recover(entryID: entry.id, expected: expected) }
      catch is CancellationError { }
      catch {
        if self.generation == expected { self.error = BackendErrorMessage.text(error) }
      }
    }
  }
  func cancel() {
    guard let entry = pending else { return }
    // The API cannot look up/cancel by idempotency key without creating a missing run.
    // Do not create a potentially billable run as a side effect of cancellation.
    guard entry.run != nil else {
      error = L10n.text("Recover this request with Try again before cancelling it. Its server status is not known yet."); return
    }
    do {
      var next = snapshot
      next.entries[next.entries.firstIndex { $0.id == entry.id }!].cancellationRequested = true
      try persist(next); suspend(); resume()
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  private func recover(entryID: UUID, expected: UUID) async throws {
    try assertAccount(); try Task.checkCancellation()
    guard var entry = snapshot.entries.first(where: { $0.id == entryID }) else { return }
    if entry.run == nil {
      // Includes retry after a lost 202 response; same key and exact same bytes.
      try await beforeSend()
      do {
        let run: BackendWire.AgentRun = try await session.domain("agent/runs", method: "POST", body: entry.body,
          headers: ["Idempotency-Key": entry.id.uuidString.lowercased()])
        try update(entryID, run: run)
      } catch let api as BackendAPIError where [400, 403, 404, 409, 422].contains(api.status) {
        var next = snapshot; next.entries[next.entries.firstIndex { $0.id == entryID }!].rejection = api.code
        try persist(next); throw api
      }
    }
    var failures = 0
    while !Task.isCancelled && generation == expected {
      try assertAccount()
      guard let current = snapshot.entries.first(where: { $0.id == entryID }), let runID = current.run?.id else { return }
      entry = current
      if entry.cancellationRequested {
        let run: BackendWire.AgentRun = try await session.domain("agent/runs/" + runID.uuidString.lowercased() + "/cancel", method: "POST")
        try update(entryID, run: run)
        if Entry.terminal(run.status) { return }
      }
      let status: BackendWire.AgentRun = try await session.domain("agent/runs/" + runID.uuidString.lowercased())
      try update(entryID, run: status)
      if Entry.terminal(status.status) { return }
      activity = L10n.text("Reviewing your training…")
      do {
        try await session.agentEvents(runID: runID, after: entry.cursor) { event in
          try self.assertAccount(); try Task.checkCancellation()
          guard self.generation == expected else { throw CancellationError() }
          var next = self.snapshot
          guard let index = next.entries.firstIndex(where: { $0.id == entryID }), event.id > next.entries[index].cursor else { return }
          next.entries[index].cursor = event.id
          try self.persist(next)
          if event.type == .toolStatus { self.activity = L10n.text("Checking your saved training data…") }
        }
        failures = 0
      } catch is CancellationError { throw CancellationError() }
      catch {
        try assertAccount(); try Task.checkCancellation()
        failures += 1
        // Status polling recovers dropped, expired or unsupported streams without another POST.
        if failures >= 4 { throw error }
      }
      try await Task.sleep(for: .seconds(min(8, max(1, failures * 2))))
    }
  }
  private func update(_ key: UUID, run: BackendWire.AgentRun) throws {
    guard let index = snapshot.entries.firstIndex(where: { $0.id == key }) else { throw BackendContractError.invalidResponse }
    guard run.task == snapshot.entries[index].request.task,
      snapshot.entries[index].run.map({ $0.id == run.id }) ?? true else { throw BackendContractError.invalidResponse }
    let input = snapshot.entries[index].request
    guard input.threadId.map({ $0 == run.threadId }) ?? true else { throw BackendContractError.invalidResponse }
    if let analyzed = run.artifact?.analyzedResult {
      guard input.task == .analyzeWorkout, analyzed.id == input.workoutResultId,
        analyzed.revision == input.expectedWorkoutRevision else { throw BackendContractError.invalidResponse }
    }
    var next = snapshot; next.entries[index].run = run; next.threadID = run.threadId
    // A GET can restore the latest snapshot even after SSE replay retention expires.
    next.entries[index].cursor = max(next.entries[index].cursor, run.lastEventId)
    try persist(next)
  }
  func loadMemories() async {
    do {
      struct Response: Decodable { var memories: [BackendWire.AgentMemory] }
      let value: Response = try await session.domain("agent/memories")
      try assertAccount(); memories = value.memories; error = nil
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  func saveMemory(id: UUID, input: BackendWire.AgentMemoryInput) async -> Bool {
    guard !busy else { return false }; busy = true; defer { busy = false }
    do {
      let _: BackendWire.AgentMemory = try await session.domain("agent/memories/" + id.uuidString.lowercased(), method: "PUT", body: OnboardingAPIClient.encode(input))
      try assertAccount(); suspend(); await loadMemories(); resume(); return error == nil
    } catch { self.error = BackendErrorMessage.text(error); return false }
  }
  func forget(_ memory: BackendWire.AgentMemory) async {
    guard !busy else { return }; busy = true; defer { busy = false }
    do {
      let _: BackendNoContent = try await session.domain("agent/memories/" + memory.id.uuidString.lowercased(), method: "DELETE", headers: ["If-Match": memory.revision.rawValue])
      try assertAccount(); suspend(); await loadMemories(); resume()
    } catch { self.error = BackendErrorMessage.text(error) }
  }
  private func persist(_ next: Snapshot) throws {
    try assertAccount()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var options: Data.WritingOptions = [.atomic]
    #if os(iOS)
    options.insert(.completeFileProtection)
    #endif
    try OnboardingAPIClient.encode(next).write(to: file, options: options)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    var url = file; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
    snapshot = next
  }
}
