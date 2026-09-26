import Foundation

/// Unassigned, pre-account recordings remain readable/exportable without entering an account's replica.
struct LegacyTrainingArchive: Identifiable {
  var id: String
  var payload: Data
  var state: TrainingState? { try? JSONDecoder().decode(TrainingState.self, from: payload) }
  var containsUserContent: Bool {
    guard let state else { return true } // Preserve undecodable records for export/recovery.
    return !state.profile.isSample || !state.results.isEmpty || !state.drafts.isEmpty || !state.messages.isEmpty
  }
  var exportText: String { String(decoding: payload, as: UTF8.self) }
}
