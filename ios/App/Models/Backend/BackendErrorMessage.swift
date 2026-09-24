import Foundation

enum BackendErrorMessage {
  static func text(_ error: Error) -> String {
    if let api = error as? BackendAPIError {
      let guidance: String
      switch api.status {
      case 401: guidance = L10n.text("Your session expired. Sign in again to continue.")
      case 429: guidance = L10n.text("Please wait before trying again.")
      case 400 where api.code.contains("OTP"), 403 where api.code.contains("OTP"): guidance = L10n.text("Check your code, or request a new one.")
      case 409: guidance = L10n.text("Your saved data changed. Refresh and review it before saving again.")
      default: guidance = L10n.text("The request couldn’t be completed. Try again.")
      }
      return guidance + " (" + api.code + (api.requestID.map { " · " + $0 } ?? "") + ")"
    }
    if let contract = error as? BackendContractError {
      switch contract {
      case .emailUnavailable: return L10n.text("Email sign-in is not enabled on this server yet.")
      case .invalidEmail: return L10n.text("Enter a valid email address.")
      case .invalidCode: return L10n.text("Enter the six-digit code from your email.")
      case .cooldown: return L10n.text("Please wait before requesting another code.")
      case .invalidOrigin: return L10n.text("Use an HTTPS server address and an API version such as v1. Simulator builds also support localhost HTTP.")
      case .pendingRequestNeedsReview: return L10n.text("A previous save needs attention. Retry it or review the server copy.")
      case .missingCatalogMapping(let item): return L10n.text("The server catalog is missing this exercise or equipment:") + " " + item
      default: return L10n.text("The server data is not compatible with this app yet. Your pending changes have been kept.")
      }
    }
    if error is URLError { return L10n.text("Couldn’t reach the server. Check the connection address and try again.") }
    return L10n.text("Your data couldn’t be opened or saved. It has not been reset.")
  }
}
