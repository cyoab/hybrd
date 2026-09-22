import Foundation

/// Athlete-supplied boundaries; never estimated from age or workout effort.
struct PersonalHeartRateZones: Codable, Equatable {
  var zone2: Int
  var zone3: Int
  var zone4: Int
  var zone5: Int
  var starts: [Int] { [zone2, zone3, zone4, zone5] }
  var isValid: Bool {
    starts.allSatisfy { (30...250).contains($0) } &&
      zip(starts, starts.dropFirst()).allSatisfy { $0 < $1 }
  }
  func label(for zone: HeartRateZone) -> String {
    switch zone {
    case .one: "Below \(zone2) bpm"
    case .two: "\(zone2)–\(zone3 - 1) bpm"
    case .three: "\(zone3)–\(zone4 - 1) bpm"
    case .four: "\(zone4)–\(zone5 - 1) bpm"
    case .five: "\(zone5)+ bpm"
    }
  }
}
