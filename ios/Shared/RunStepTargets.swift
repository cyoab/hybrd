import Foundation

/// Numeric prescription targets retain canonical units; text is presentation only.
struct RunStepTargets: Codable, Equatable {
  var distanceM: Double?
  var durationS: Int?
  var paceMinSPerKm: Double?
  var paceMaxSPerKm: Double?
  var hrMinBpm: Int?
  var hrMaxBpm: Int?
  var rpeMin: Double?
  var rpeMax: Double?

  var completion: RunStepCompletion? {
    if let durationS, distanceM == nil, durationS > 0 { return .duration(durationS) }
    if let distanceM, durationS == nil, distanceM.isFinite, distanceM > 0 { return .distance(distanceM) }
    // v1 does not define whether combined thresholds mean first or both. Never guess.
    return nil
  }
  func summary(units: TrainingUnits) -> String {
    var parts: [String] = []
    if let distanceM { parts.append(units.distanceText(distanceM, decimals: 2)) }
    if let durationS { parts.append(RunRecording.clock(Double(durationS))) }
    if let pace = Self.range(paceMinSPerKm, paceMaxSPerKm, format: { units.paceNumber($0) }) { parts.append(pace + " /" + units.distance.symbol) }
    if let heart = Self.range(hrMinBpm, hrMaxBpm, format: { String($0) }) { parts.append(heart + " bpm") }
    if let effort = Self.range(rpeMin, rpeMax, format: { $0.formatted() }) { parts.append("RPE " + effort) }
    return parts.joined(separator: " · ")
  }
  static func range<Value: Equatable>(_ lower: Value?, _ upper: Value?, format: (Value) -> String) -> String? {
    switch (lower, upper) {
    case (nil, nil): nil
    case (.some(let value), nil): "≥ " + format(value)
    case (nil, .some(let value)): "≤ " + format(value)
    case (.some(let a), .some(let b)): a == b ? format(a) : format(a) + "–" + format(b)
    }
  }
}

enum RunStepCompletion: Codable, Equatable {
  case duration(Int)
  case distance(Double)
}
