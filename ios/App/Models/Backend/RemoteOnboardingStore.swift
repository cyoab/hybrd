import Foundation
import Observation

/// Connected setup state, intentionally isolated from the anonymous preview and live training store.
@MainActor @Observable final class RemoteOnboardingStore {
  private(set) var state: BackendWire.OnboardingState?
  private(set) var isWorking = false
  private(set) var hasPendingRequest: Bool
  @ObservationIgnored private var snapshot: OnboardingRequestJournal.Snapshot
  @ObservationIgnored private let journal: OnboardingRequestJournal
  @ObservationIgnored private let api: OnboardingAPIClient

  init(api: OnboardingAPIClient, directory: URL) throws {
    try api.assertAccount()
    self.api = api
    journal = OnboardingRequestJournal(directory: directory, scope: api.scope)
    snapshot = try journal.load() // Corruption is an error; never silently overwrite an unreadable draft.
    state = snapshot.remote; hasPendingRequest = snapshot.pending != nil
  }
  /// Call after account bootstrap/device registration/canonical pull. Pending work stays separate.
  func restore() async throws {
    guard !isWorking else { throw BackendContractError.requestInFlight }
    isWorking = true; defer { isWorking = false }
    let remote = try await api.getOnboarding()
    var next = snapshot; next.remote = remote
    try persist(next)
  }
  func saveReviewedDraft(_ draft: BackendWire.OnboardingDraft, step: BackendWire.OnboardingStateStep) async throws {
    try requireNewRequest()
    guard let state else { throw BackendContractError.restoreRequired }
    guard state.status != .completed else { throw BackendContractError.alreadyCompleted }
    let request = BackendWire.SaveOnboardingDraft(baseRevision: state.draftRevision, step: step, draft: draft)
    try prepare(.save, body: OnboardingAPIClient.encode(request))
    try await retryPending()
  }
  func completeReviewedDraft(deviceID: UUID, catalogVersion: Int, policyID: UUID) async throws {
    try requireNewRequest()
    guard let state else { throw BackendContractError.restoreRequired }
    guard state.status != .completed else { throw BackendContractError.alreadyCompleted }
    guard let revision = state.draftRevision else { throw BackendContractError.restoreRequired }
    guard state.reviewIssues.isEmpty else { throw BackendContractError.pendingRequestNeedsReview }
    let request = BackendWire.CompleteOnboarding(draftRevision: revision, deviceId: deviceID,
      catalogVersion: catalogVersion, policyVersionId: policyID)
    try prepare(.complete, body: OnboardingAPIClient.encode(request))
    try await retryPending()
  }
  /// Explicit retry, never a loop. Authentication errors/backoff/conflicts are surfaced to the caller.
  func retryPending() async throws {
    guard !isWorking else { throw BackendContractError.requestInFlight }
    guard let pending = snapshot.pending else { return }
    try api.assertAccount(); try journal.save(snapshot) // Must be durable before every send.
    isWorking = true; defer { isWorking = false }
    do {
      switch pending.kind {
      case .save:
        _ = try await api.replaySave(body: pending.body, key: pending.key)
        // A replay's revision may be old; GET authoritative state before clearing the request.
        let remote = try await api.getOnboarding()
        var next = snapshot; next.remote = remote; next.pending = nil
        try persist(next)
      case .complete:
        let receipt = try await api.replayCompletion(body: pending.body, key: pending.key)
        let remote = BackendWire.OnboardingState(schemaVersion: .value1, status: .completed,
          step: .membership, completion: receipt, reviewIssues: [])
        var next = snapshot; next.remote = remote; next.pending = nil
        try persist(next)
      }
    } catch let error as BackendAPIError where error.recovery == .recoverCompletion {
      let remote = try await api.getOnboarding()
      guard remote.status == .completed, remote.completion != nil else { throw error }
      var next = snapshot; next.remote = remote; next.pending = nil
      try persist(next)
    }
    // Never apply receipt.latestSequence to a sync cursor or grant access/activate a plan here.
  }
  /// Only after showing restored server state and the pending draft to the athlete for review.
  func discardPendingAfterReview() throws {
    guard !isWorking else { throw BackendContractError.requestInFlight }
    try api.assertAccount()
    var next = snapshot; next.pending = nil; try persist(next)
  }
  var pendingDraftForReview: BackendWire.SaveOnboardingDraft? {
    guard let pending = snapshot.pending, pending.kind == .save else { return nil }
    return try? JSONDecoder().decode(BackendWire.SaveOnboardingDraft.self, from: pending.body)
  }
  private func requireNewRequest() throws {
    try api.assertAccount()
    guard !isWorking else { throw BackendContractError.requestInFlight }
    guard snapshot.pending == nil else { throw BackendContractError.pendingRequestNeedsReview }
  }
  private func prepare(_ kind: OnboardingRequestJournal.Pending.Kind, body: Data) throws {
    var next = snapshot; next.pending = .init(key: UUID(), kind: kind, body: body); try persist(next)
  }
  private func persist(_ next: OnboardingRequestJournal.Snapshot) throws {
    try api.assertAccount(); try journal.save(next)
    snapshot = next; state = next.remote; hasPendingRequest = next.pending != nil
  }
}
