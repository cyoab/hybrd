import Foundation

/// PostgreSQL bigint revision, kept out of floating-point JSON numbers.
struct BackendRevision: Codable, Equatable, Comparable, Sendable {
  let rawValue: String
  init(_ value: String) throws {
    guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
          value == "0" || value.first != "0", Int64(value) != nil else {
      throw BackendContractError.invalidRevision
    }
    rawValue = value
  }
  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue.count == rhs.rawValue.count ? lhs.rawValue < rhs.rawValue : lhs.rawValue.count < rhs.rawValue.count
  }
  init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
  func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
