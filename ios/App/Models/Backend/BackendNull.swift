import Foundation

/// A field whose contract allows only JSON null (for example undated Strava weight).
struct BackendNull: Codable, Equatable, Sendable {
  init() {}
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    guard c.decodeNil() else { throw BackendContractError.unexpectedValue }
  }
  func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encodeNil() }
}
