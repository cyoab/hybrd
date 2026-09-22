import Foundation

/// A composition of prescribed time or sets, never measured time in zone or completed work.
struct SessionBreakdown {
  var kind: WorkoutKind
  var parts: [Part]
  var total: Int { parts.reduce(0) { $0 + $1.amount } }

  init(workout: TrainingWorkout) {
    kind = workout.kind
    if workout.kind == .run {
      let steps = RunTimeline(segments: workout.segments).steps
      let zones: [HeartRateZone?] = HeartRateZone.allCases.map { $0 } + [nil]
      parts = zones.compactMap { zone in
        let amount = steps.filter { $0.segment.heartRateZone == zone }.reduce(0) { $0 + $1.seconds }
        guard amount > 0 else { return nil }
        let segments = workout.segments.filter { $0.heartRateZone == zone }
        return Part(id: zone.map { "zone\($0.rawValue)" } ?? "unassigned",
          title: zone?.title ?? "Unassigned", subtitle: zone?.name ?? "No HR target",
          amount: amount, tone: Self.tone(for: zone),
          detail: segments.map { $0.displayTitle + " · " + $0.targetSummary }.joined(separator: "\n"))
      }
    } else {
      let palette: [Tone] = [.violet, .sky, .mint, .terra, .gold]
      parts = workout.exercises.enumerated().compactMap { index, exercise in
        guard !exercise.sets.isEmpty else { return nil }
        return Part(id: exercise.id.uuidString, title: exercise.name,
          amount: exercise.sets.count, tone: palette[index % palette.count],
          detail: "\(exercise.sets.reduce(0) { $0 + $1.reps }) prescribed reps · \(exercise.restSeconds) sec between sets\n\(exercise.note)")
      }
    }
  }

  func share(of part: Part) -> Double { total > 0 ? Double(part.amount) / Double(total) : 0 }

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
    let minuteText = "\(minutes) " + (minutes == 1 ? "minute" : "minutes")
    return seconds == 0 ? minuteText : minuteText + ", \(seconds) " + (seconds == 1 ? "second" : "seconds")
  }

  static func tone(for zone: HeartRateZone?) -> Tone {
    switch zone {
    case .one: .sky
    case .two: .mint
    case .three: .gold
    case .four: .terra
    case .five: .violet
    case nil: .neutral
    }
  }

  struct Part: Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var amount: Int
    var tone: Tone
    var detail: String
  }

  enum Tone { case sky, mint, gold, terra, violet, neutral }
}
