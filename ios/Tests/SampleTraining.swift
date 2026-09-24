import Foundation

enum SampleTraining {
  static func makePlan(profile: TrainingProfile, start: Date = Date()) -> TrainingPlan {
    let first = Calendar.current.startOfDay(for: start)
    var workouts: [TrainingWorkout] = []
    for week in 0..<4 {
      let day = TrainingEngine.date(first, offset: week * 7)
      let recovery = week == 3
      let repetitions = recovery ? 2 : 3
      workouts.append(TrainingWorkout(
        date: day, kind: .run, title: "Threshold intervals",
        purpose: "A controlled quality session. Keep the work intervals consistent, and use each recovery to reset.",
        minutes: 25 + repetitions * 11, distanceMeters: recovery ? 8_800 : 11_400,
        effort: "Threshold work", isKey: true,
        segments: [
          RunSegment(title: "Warm-up", seconds: 900, cue: "Start with easy, conversational running.", phase: .warmUp, target: "easy", heartRateZone: .two),
          RunSegment(title: "Work", seconds: 480, cue: "A controlled, comfortably hard effort. This pace is illustrative sample data.", phase: .work, repetitions: repetitions, target: "@ 4:22–4:30", heartRateZone: .four),
          RunSegment(title: "Recovery", seconds: 180, cue: "Jog easily after each work interval.", phase: .recovery, repetitions: repetitions, target: "jog", heartRateZone: .one),
          RunSegment(title: "Cool-down", seconds: 600, cue: "Let your breathing settle as you ease the pace.", phase: .coolDown, target: "easy", heartRateZone: .one)
        ], scheduledMinutes: 390, runType: .intervals))
      var upper = TrainingEngine.strengthWorkout(on: day, lower: false, minutes: 45, goal: .build)
      upper.title = "Upper push"
      upper.isOptional = true
      upper.scheduledMinutes = 1_080
      upper.purpose = "Optional upper-body work after your key run. Keep three reps in reserve and skip it if you need more recovery."
      workouts.append(upper)

      for (offset, title, distance) in [(1, "Easy run", 6_500), (4, "Aerobic base", 8_100), (5, "Long easy run", 14_000)] {
        let meters = recovery ? Int(Double(distance) * 0.75) : distance
        let minutes = Int(Double(meters) / 165)
        workouts.append(TrainingWorkout(
          date: TrainingEngine.date(day, offset: offset), kind: .run, title: title,
          purpose: "Keep your effort conversational. Easy running supports the week without competing with your strength sessions.",
          minutes: minutes, distanceMeters: meters, effort: "Easy running", isKey: offset == 5,
          segments: [
            RunSegment(title: "Warm-up", seconds: 300, cue: "Ease into the run.", phase: .warmUp, target: "easy", heartRateZone: .two),
            RunSegment(title: "Easy running", seconds: (minutes - 10) * 60, cue: "You should be able to speak in full sentences.", phase: .easy, target: "easy", heartRateZone: .two),
            RunSegment(title: "Cool-down", seconds: 300, cue: "Gradually slow down.", phase: .coolDown, target: "easy", heartRateZone: .one)
          ], scheduledMinutes: 420, runType: offset == 5 ? .long : .easy))
      }
      var lower = TrainingEngine.strengthWorkout(on: TrainingEngine.date(day, offset: 2), lower: true, minutes: 50, goal: .build)
      lower.scheduledMinutes = 1_080
      workouts.append(lower)
      var pull = TrainingEngine.strengthWorkout(on: TrainingEngine.date(day, offset: 6), lower: false, minutes: 45, goal: .build)
      pull.title = "Upper pull"
      pull.scheduledMinutes = 1_020
      workouts.append(pull)
    }
    return TrainingPlan(reason: "Sample hybrid training block", profile: profile, workouts: workouts)
  }
}

// Legacy/demo fixtures belong to executable checks, never to an app target.
extension TrainingState {
  static func sample() -> TrainingState {
    let profile = TrainingProfile()
    return TrainingState(profile: profile, plans: [SampleTraining.makePlan(profile: profile)])
  }
}
