import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
  case chest, back, shoulders, biceps, triceps, core, quadriceps, hamstrings, glutes, calves
  var id: String { rawValue }
  var title: String { L10n.content(rawValue.capitalized) }
  var isPosterior: Bool { [.back, .triceps, .hamstrings, .glutes, .calves].contains(self) }
  var isLower: Bool { [.quadriceps, .hamstrings, .glutes, .calves].contains(self) }
  var catalogMuscles: Set<String> {
    switch self {
    case .back: ["lats", "middle back", "lower back", "traps"]
    case .core: ["abdominals"]
    default: [rawValue]
    }
  }
}
