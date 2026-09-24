import Foundation

enum BackendContractError: Error, Equatable {
  case invalidRevision, invalidDate, unexpectedValue, invalidOrigin, invalidResponse
  case accountChanged, restoreRequired, pendingRequestNeedsReview, alreadyCompleted
  case emailUnavailable, invalidEmail, invalidCode, cooldown
  case requestInFlight
  case invalidDraft, missingCatalogMapping(String), invalidBaselinePeriod
}
