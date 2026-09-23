import Foundation

struct StrengthPersonalBest: Codable, Equatable, Identifiable {
  var id = UUID()
  var exerciseID: String
  var localizedExerciseName: String { L10n.content(exerciseName) }
  var exerciseName: String
  var kilograms: Double
  var reps: Int
  var source: RecordSource = .manual
  var isValid: Bool {
    !exerciseID.isEmpty && !exerciseName.isEmpty && kilograms.isFinite &&
      (0...1_000).contains(kilograms) && (1...100).contains(reps)
  }
  var summary: String { L10n.text("\(kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg × \(reps)") }
}

enum RecordSource: String, Codable { case manual, logged }

enum LoggedStrengthRecords {
  static func candidates(from results: [WorkoutResult]) -> [StrengthPersonalBest] {
    let sets = results.filter { $0.kind == .strength && $0.status != .skipped }.flatMap(\.sets)
      .filter { $0.isComplete && $0.kilograms.isFinite && (0...1_000).contains($0.kilograms) && (1...100).contains($0.reps) }
    return Dictionary(grouping: sets, by: \.exerciseName).compactMap { name, sets in
      guard let best = sets.max(by: {
        $0.kilograms == $1.kilograms ? $0.reps < $1.reps : $0.kilograms < $1.kilograms
      }) else { return nil }
      return StrengthPersonalBest(exerciseID: "logged:" + name, exerciseName: name,
        kilograms: best.kilograms, reps: best.reps, source: .logged)
    }.sorted { $0.exerciseName < $1.exerciseName }
  }
}
