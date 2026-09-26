import Foundation

struct StrengthSetTargets: Codable, Equatable {
  enum Kind: String, Codable { case warmup, working, backoff }
  var setNumber: Int
  var setKind: Kind
  var repsMin: Int?
  var repsMax: Int?
  var loadKg: Double?
  var loadPercentE1rm: Double?
  var rpeMin: Double?
  var rpeMax: Double?
  var rirMin: Double?
  var rirMax: Double?
  var restS: Int?
  var notes: String?

  func summary(units: TrainingUnits) -> String {
    var parts = [L10n.content(setKind.rawValue.capitalized)]
    if let reps = RunStepTargets.range(repsMin, repsMax, format: { String($0) }) { parts.append(reps + " " + L10n.text("reps")) }
    if let loadKg { parts.append(units.weightText(loadKg)) }
    if let loadPercentE1rm { parts.append(loadPercentE1rm.formatted() + "% e1RM") }
    if let rir = RunStepTargets.range(rirMin, rirMax, format: { $0.formatted() }) { parts.append(rir + " RIR") }
    if let effort = RunStepTargets.range(rpeMin, rpeMax, format: { $0.formatted() }) { parts.append("RPE " + effort) }
    if let restS { parts.append(L10n.text("\(restS)s rest")) }
    return parts.joined(separator: " · ")
  }
}

struct ExerciseSubstitution: Codable, Equatable {
  var exerciseId: UUID
  var priority: Int
  var rationale: String?
}
