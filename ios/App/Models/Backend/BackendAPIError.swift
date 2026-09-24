import Foundation

struct BackendAPIError: Error, Equatable {
  var status: Int
  var code: String
  var requestID: String?
  var details: BackendJSONValue?
  var retryAfterSeconds: TimeInterval?

  var recovery: Recovery {
    if status == 401 { return .signIn }
    switch code {
    case "ONBOARDING_REVISION_CONFLICT": return .reviewDraft
    case "IMPORT_PREVIEW_EXPIRED", "IMPORT_REVIEW_REQUIRED": return .reviewImport
    case "UNSUPPORTED_CATALOG_MAPPING": return .refreshCatalog
    case "ONBOARDING_ALREADY_COMPLETED": return .recoverCompletion
    case "ONBOARDING_EXISTING_SETUP": return .restoreExistingSetup
    case "DEVICE_UNAVAILABLE": return .registerDevice
    default: return status == 429 || status >= 500 ? .retry : .correctRequest
    }
  }
  enum Recovery { case signIn, reviewDraft, reviewImport, refreshCatalog, recoverCompletion, restoreExistingSetup, registerDevice, retry, correctRequest }

  static func from(_ response: HTTPURLResponse, data: Data, now: Date = Date()) -> Self {
    struct Envelope: Decodable {
      struct Detail: Decodable { var code: String; var details: BackendJSONValue?; var requestId: String? }
      var error: Detail
    }
    struct AuthError: Decodable { var code: String }
    let auth = try? JSONDecoder().decode(AuthError.self, from: data)
    let parsed = try? JSONDecoder().decode(Envelope.self, from: data).error
    let header = response.value(forHTTPHeaderField: "Retry-After")
    var delay = header.flatMap(Double.init).flatMap { $0.isFinite ? max(0, $0) : nil }
    if delay == nil, let header {
      let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
      f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
      delay = f.date(from: header).map { max(0, $0.timeIntervalSince(now)) }
    }
    return Self(status: response.statusCode, code: parsed?.code ?? auth?.code ?? "HTTP_\(response.statusCode)",
      requestID: response.value(forHTTPHeaderField: "X-Request-Id") ?? parsed?.requestId,
      details: parsed?.details, retryAfterSeconds: delay)
  }
}
