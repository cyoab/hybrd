import Foundation

enum BackendContractError: Error, Equatable {
  case invalidRevision, invalidDate, unexpectedValue, invalidOrigin, invalidResponse
  case accountChanged, restoreRequired, pendingRequestNeedsReview, alreadyCompleted
  case requestInFlight
  case invalidDraft, missingCatalogMapping(String), invalidBaselinePeriod
}
