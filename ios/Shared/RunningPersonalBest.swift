import Foundation

struct RunningPersonalBest: Codable, Equatable, Identifiable {
  var distance: RunRecordDistance
  var seconds: Int
  var id: RunRecordDistance { distance }
  var time: String { Self.format(seconds) }
  static func format(_ seconds: Int) -> String {
    seconds >= 3_600 ? String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60) :
      String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
  static func parse(_ text: String) -> Int? {
    let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
    guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
    let values = parts.compactMap { Int($0) }
    guard values.count == parts.count, values.allSatisfy({ (0...2_880).contains($0) }),
      values.last! < 60, (values.count == 2 || values[1] < 60) else { return nil }
    let total = values.reduce(0) { $0 * 60 + $1 }
    return (1...172_800).contains(total) ? total : nil
  }
}

enum RunRecordDistance: String, Codable, CaseIterable, Identifiable {
  case mile = "1 mile", fiveK = "5K", tenK = "10K", half = "Half marathon", marathon = "Marathon"
  var id: String { rawValue }
}
