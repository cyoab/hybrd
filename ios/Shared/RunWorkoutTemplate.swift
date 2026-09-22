import Foundation

/// Original, time-based recipes. They never infer pace, distance, or personal BPM ranges.
enum RunWorkoutTemplate: String, CaseIterable, Identifiable {
  case easyThirty, recoveryTwenty, longSixty, tempoRepeats, steadyTempo, twoMinuteIntervals, hillRepeats, progression

  var id: String { rawValue }

  var type: RunWorkoutType {
    switch self {
    case .easyThirty: .easy
    case .recoveryTwenty: .recovery
    case .longSixty: .long
    case .tempoRepeats, .steadyTempo: .tempo
    case .twoMinuteIntervals: .intervals
    case .hillRepeats: .hills
    case .progression: .progression
    }
  }

  var title: String {
    switch self {
    case .easyThirty: "Easy 30"
    case .recoveryTwenty: "Recovery 20"
    case .longSixty: "Long & easy"
    case .tempoRepeats: "Tempo repeats"
    case .steadyTempo: "Steady tempo"
    case .twoMinuteIntervals: "Two-minute intervals"
    case .hillRepeats: "Hill repeats"
    case .progression: "Build your rhythm"
    }
  }

  var subtitle: String {
    switch self {
    case .easyThirty: "Find your flow"
    case .recoveryTwenty: "Keep it gentle"
    case .longSixty: "Time on your feet"
    case .tempoRepeats: "3 × 5 min of focus"
    case .steadyTempo: "One sustained effort"
    case .twoMinuteIntervals: "6 × 2 min of quality"
    case .hillRepeats: "6 controlled climbs"
    case .progression: "Easy to steady to strong"
    }
  }

  var purpose: String {
    switch self {
    case .easyThirty: "Build your aerobic base with relaxed, conversational running. Let your heart rate guide the pace."
    case .recoveryTwenty: "A short, gentle run to keep moving between harder days. Stay relaxed and walk whenever you need to."
    case .longSixty: "Build endurance with an hour of easy running. Settle into a sustainable rhythm and keep the finish controlled."
    case .tempoRepeats: "Practice holding a comfortably hard effort in three focused blocks, with easy recoveries to reset."
    case .steadyTempo: "Develop sustained running with a steady middle block. Stay controlled from the first minute to the last."
    case .twoMinuteIntervals: "Alternate short, controlled work with easy jogging. Aim for consistent repetitions, rather than a sprint finish."
    case .hillRepeats: "Use a gentle hill to practice strong, controlled running. Recover on the way down and take extra time to return safely to the start."
    case .progression: "Begin easy, settle into steady running, then finish the main block with a short controlled effort before cooling down."
    }
  }

  var segments: [RunSegment] {
    let warm = RunSegment(title: "Warm-up", seconds: 600, cue: "Ease into conversational running.", phase: .warmUp, heartRateZone: .two)
    let cool = RunSegment(title: "Cool-down", seconds: 300, cue: "Gradually slow down and let your breathing settle.", phase: .coolDown, heartRateZone: .one)
    switch self {
    case .easyThirty, .longSixty:
      var opening = warm
      opening.seconds = 300
      return [opening,
        RunSegment(title: "Easy running", seconds: self == .easyThirty ? 1_200 : 3_000,
          cue: "Keep a conversational pace throughout.", phase: .easy, heartRateZone: .two), cool]
    case .recoveryTwenty:
      return [RunSegment(title: "Ease in", seconds: 300, cue: "Start gently; walking is welcome.", phase: .warmUp, heartRateZone: .one),
        RunSegment(title: "Recovery jog", seconds: 600, cue: "Keep your breathing relaxed and your stride comfortable.", phase: .easy, heartRateZone: .one), cool]
    case .tempoRepeats:
      return [warm,
        RunSegment(title: "Tempo", seconds: 300, cue: "Settle into a comfortably hard, repeatable effort.", phase: .work, repetitions: 3, heartRateZone: .four),
        RunSegment(title: "Recovery", seconds: 120, cue: "Jog easily after each block.", phase: .recovery, repetitions: 3, heartRateZone: .one), cool]
    case .steadyTempo:
      return [warm, RunSegment(title: "Steady tempo", seconds: 900, cue: "Stay in control at a steady, sustained effort.", phase: .work, heartRateZone: .three), cool]
    case .twoMinuteIntervals:
      return [warm,
        RunSegment(title: "Controlled interval", seconds: 120, cue: "Build smoothly. Heart rate can lag on short reps; do not sprint to chase the zone.", phase: .work, repetitions: 6, heartRateZone: .four),
        RunSegment(title: "Recovery", seconds: 90, cue: "Jog or walk easily after each interval.", phase: .recovery, repetitions: 6, heartRateZone: .one), cool]
    case .hillRepeats:
      return [warm,
        RunSegment(title: "Uphill", seconds: 60, cue: "Run tall with short, controlled steps. Heart rate is a guide, not a number to chase during a short climb.", phase: .work, repetitions: 6, heartRateZone: .four),
        RunSegment(title: "Return & recover", seconds: 90, cue: "Walk or jog back down. This is a guide; take longer if needed to return safely and recover.", phase: .recovery, repetitions: 6, heartRateZone: .one), cool]
    case .progression:
      var opening = warm
      opening.seconds = 300
      return [opening,
        RunSegment(title: "Easy rhythm", seconds: 600, cue: "Let the run come to you; keep it conversational.", phase: .easy, heartRateZone: .two),
        RunSegment(title: "Steady rhythm", seconds: 600, cue: "Gently build to a steady, controlled pace.", phase: .work, heartRateZone: .three),
        RunSegment(title: "Strong finish", seconds: 300, cue: "Finish the main block comfortably hard, with no sprint.", phase: .work, heartRateZone: .four), cool]
    }
  }

  var minutes: Int { RunTimeline(segments: segments).totalSeconds / 60 }

  func workout(on date: Date) -> TrainingWorkout {
    TrainingWorkout(date: Calendar.current.startOfDay(for: date), kind: .run, title: title,
      purpose: purpose, minutes: minutes,
      effort: type.title, isKey: ![.easy, .recovery].contains(type),
      segments: segments, runType: type)
  }
}
