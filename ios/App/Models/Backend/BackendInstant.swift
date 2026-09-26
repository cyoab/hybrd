import Foundation

/// Preserve the provider's RFC3339 precision/offset while allowing expiry comparisons.
struct BackendInstant: Codable, Equatable, Sendable {
  let rawValue: String
  let date: Date
  init(_ value: String) throws {
    guard value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else {
      throw BackendContractError.invalidDate
    }
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var parsed = formatter.date(from: value)
    if parsed == nil { formatter.formatOptions = [.withInternetDateTime]; parsed = formatter.date(from: value) }
    guard let parsed else { throw BackendContractError.invalidDate }
    rawValue = value; date = parsed
  }
  init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
  func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
