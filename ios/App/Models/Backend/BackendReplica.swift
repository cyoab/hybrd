import Foundation
import Observation

/// Canonical pages/cursor and optimistic edits/outbox are committed atomically in one account file.
@MainActor @Observable final class BackendReplica {
  struct Snapshot: Codable {
    var version = 1
    var scope: BackendAccountScope
    var deviceID = UUID()
    var cursor = try! BackendRevision("0")
    var records: [String: BackendWire.SyncChange] = [:]
    var outbox: [BackendMutation] = []
    var outcomes: [BackendWire.MutationResult] = []
    var local: TrainingState?
  }
  private(set) var snapshot: Snapshot
  private(set) var syncing = false
  private let file: URL
  private let assertAccount: () throws -> Void
  init(directory: URL, scope: BackendAccountScope, assertAccount: @escaping () throws -> Void) throws {
    self.assertAccount = assertAccount
    file = OnboardingRequestJournal(directory: directory, scope: scope).file
    if FileManager.default.fileExists(atPath: file.path) {
      snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
      guard snapshot.version == 1, snapshot.scope == scope else { throw BackendContractError.accountChanged }
    } else { snapshot = Snapshot(scope: scope) }
    try persist(snapshot)
  }
  var records: [BackendWire.SyncChange] { Array(snapshot.records.values) }
  func revision(_ type: BackendMutation.Entity, _ id: UUID) -> BackendRevision? {
    snapshot.records[type.rawValue + ":" + id.uuidString]?.metadata.revision
  }
  func enqueue(_ mutations: [BackendMutation], local: TrainingState) throws {
    guard snapshot.outbox.isEmpty, !syncing else { throw BackendContractError.pendingRequestNeedsReview }
    var next = snapshot; next.outbox = mutations; next.local = local; next.outcomes = []; try persist(next)
  }
  func saveLocal(_ local: TrainingState) throws { var next = snapshot; next.local = local; try persist(next) }
  func discardRejectedChanges() throws {
    guard !syncing, !snapshot.outcomes.isEmpty else { throw BackendContractError.pendingRequestNeedsReview }
    var next = snapshot; next.outbox = []; next.outcomes = []; next.local = nil; try persist(next)
  }
  func sync(session: BackendSession) async throws {
    guard !syncing else { throw BackendContractError.requestInFlight }
    try assertAccount(); syncing = true; defer { syncing = false }
    if !snapshot.outbox.isEmpty, snapshot.outcomes.isEmpty {
      // Sequential operations allow create-block → create-plan → activate-plan and exact retry after each lost response.
      while let mutation = snapshot.outbox.first {
        struct Push: Encodable { var deviceId: UUID; var mutations: [BackendMutation] }
        let response: BackendWire.SyncPushResponse = try await session.domain("sync/push", method: "POST",
          body: OnboardingAPIClient.encode(Push(deviceId: snapshot.deviceID, mutations: [mutation])))
        try assertAccount()
        guard response.results.count == 1, let result = response.results.first, result.mutationId == mutation.id else { throw BackendContractError.invalidResponse }
        var next = snapshot
        if result.status == .applied { next.outbox.removeFirst() }
        else { next.outcomes.append(result) }
        try persist(next)
        if result.status != .applied { break }
      }
    }
    do { try await pull(session: session) }
    catch let error as BackendAPIError where error.code == "CURSOR_AHEAD" {
      var next = snapshot; next.cursor = try BackendRevision("0"); next.records = [:]; try persist(next)
      try await pull(session: session)
    }
  }
  private func pull(session: BackendSession) async throws {
    repeat {
      let page: BackendWire.SyncPullResponse = try await session.domain("sync/pull", query: [
        .init(name: "deviceId", value: snapshot.deviceID.uuidString), .init(name: "cursor", value: snapshot.cursor.rawValue), .init(name: "limit", value: "50")])
      try assertAccount()
      guard page.nextCursor >= snapshot.cursor, !page.hasMore || page.nextCursor > snapshot.cursor else { throw BackendContractError.invalidResponse }
      var next = snapshot
      for change in page.changes {
        let meta = change.metadata
        guard meta.sequence > snapshot.cursor, meta.sequence <= page.nextCursor else { throw BackendContractError.invalidResponse }
        let key = meta.type + ":" + meta.id.uuidString
        if let previous = next.records[key]?.metadata {
          if let old = previous.revision, let new = meta.revision, old > new { continue }
          if previous.sequence > meta.sequence { continue }
        }
        next.records[key] = change // Retain tombstones to prevent an older hydrated record being resurrected.
      }
      next.cursor = page.nextCursor; try persist(next)
      struct Ack: Encodable { var deviceId: UUID; var cursor: BackendRevision }
      let _: BackendNoContent = try await session.domain("sync/ack", method: "POST",
        body: OnboardingAPIClient.encode(Ack(deviceId: next.deviceID, cursor: next.cursor)))
      if !page.hasMore { break }
    } while !Task.isCancelled
    try Task.checkCancellation()
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
