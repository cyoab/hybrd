import Foundation

/// A composition of prescribed time or sets, never completion or recorded effort.
struct SessionBreakdown {
  var kind: WorkoutKind
  var parts: [Part]
  var total: Int { parts.reduce(0) { $0 + $1.amount } }

  init(workout: TrainingWorkout) {
    kind = workout.kind
    if workout.kind == .run {
      let steps = RunTimeline(segments: workout.segments).steps
      parts = RunGroup.allCases.compactMap { group in
        let amount = steps.filter { RunGroup(phase: $0.segment.phase) == group }.reduce(0) { $0 + $1.seconds }
        guard amount > 0 else { return nil }
        let segments = workout.segments.filter { RunGroup(phase: $0.phase) == group }
        return Part(id: group.rawValue, title: group.title, amount: amount, tone: group.tone,
          detail: segments.map { $0.displayTitle + " · " + $0.targetSummary }.joined(separator: "\n"))
      }
    } else {
      parts = workout.exercises.enumerated().compactMap { index, exercise in
        guard !exercise.sets.isEmpty else { return nil }
        return Part(id: exercise.id.uuidString, title: exercise.name, amount: exercise.sets.count,
          tone: Tone.allCases[index % Tone.allCases.count],
          detail: "\(exercise.sets.reduce(0) { $0 + $1.reps }) prescribed reps · \(exercise.restSeconds) sec between sets\n\(exercise.note)")
      }
    }
  }

  func share(of part: Part) -> Double {
    total > 0 ? Double(part.amount) / Double(total) : 0
  }

  func value(for amount: Int) -> String {
    if kind == .strength { return amount.formatted() }
    if amount.isMultiple(of: 60) { return (amount / 60).formatted() }
    return "\(amount / 60):\(String(format: "%02d", amount % 60))"
  }

  func unit(for amount: Int) -> String {
    if kind == .strength { return amount == 1 ? "set" : "sets" }
    return amount.isMultiple(of: 60) ? "min" : "min:sec"
  }

  func spokenValue(for amount: Int) -> String {
    if kind == .strength { return "\(amount) " + unit(for: amount) }
    let minutes = amount / 60
    let seconds = amount % 60
    return seconds == 0 ? "\(minutes) minutes" : "\(minutes) minutes, \(seconds) seconds"
  }

  struct Part: Identifiable {
    var id: String
    var title: String
    var amount: Int
    var tone: Tone
    var detail: String
  }

  enum Tone: CaseIterable {
    case terra, ink, stone, sand
  }

  private enum RunGroup: String, CaseIterable {
    case easy, work, recovery, unspecified

    init(phase: RunSegmentPhase?) {
      switch phase {
      case .warmUp, .easy, .coolDown: self = .easy
      case .work: self = .work
      case .recovery: self = .recovery
      case nil: self = .unspecified
      }
    }

    var title: String {
      switch self {
      case .easy: "Easy & prep"
      case .work: "Work"
      case .recovery: "Recovery"
      case .unspecified: "Running"
      }
    }

    var tone: Tone {
      switch self {
      case .easy: .stone
      case .work: .terra
      case .recovery: .ink
      case .unspecified: .sand
      }
    }
  }
}
