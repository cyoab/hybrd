import Foundation

struct BackendFalse: Codable, Equatable, Sendable {
  init() {}
  init(from decoder: Decoder) throws {
    guard try !decoder.singleValueContainer().decode(Bool.self) else { throw BackendContractError.unexpectedValue }
  }
  func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(false) }
}
