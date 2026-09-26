import Foundation

/// A calendar date, never implicitly converted to an instant in the phone's timezone.
struct BackendDay: Codable, Equatable, Comparable, Sendable {
  let rawValue: String
  init(_ value: String) throws {
    guard value.count == 10, value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else {
      throw BackendContractError.invalidDate
    }
    let parts = value.split(separator: "-").compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
    guard parts[0] > 0, let date = calendar.date(from: components),
          calendar.component(.year, from: date) == parts[0],
          calendar.component(.month, from: date) == parts[1],
          calendar.component(.day, from: date) == parts[2] else {
      throw BackendContractError.invalidDate
    }
    rawValue = value
  }
  init(date: Date, timeZone: TimeZone) throws {
    let format = DateFormatter(); format.calendar = Calendar(identifier: .gregorian)
    format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = timeZone; format.dateFormat = "yyyy-MM-dd"
    try self.init(format.string(from: date))
  }
  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
  func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
