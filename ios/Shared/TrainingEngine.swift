import Foundation

enum TrainingEngine {
  static func startOfWeek(containing date: Date) -> Date {
    var calendar = Calendar.current
    calendar.firstWeekday = 2
    return calendar.dateInterval(of: .weekOfYear, for: date)!.start
  }

  static func date(_ start: Date, offset: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: offset, to: start)!
  }

  static func makePlan(profile: TrainingProfile, start: Date = Date(), basePlanID: UUID? = nil) -> TrainingPlan {
    let firstDay = Calendar.current.startOfDay(for: start)
    var workouts: [TrainingWorkout] = []
    for week in 0..<4 {
      let days = (0..<7).map { date(firstDay, offset: week * 7 + $0) }
        .filter { profile.availableDays.contains(Calendar.current.component(.weekday, from: $0)) }
      let strengthCount = min(profile.strengthDays, max(0, days.count - 1))
      let runCount = days.count - strengthCount
      let totalMeters = Int(profile.weeklyKilometers * 1_000 * (week == 3 ? 0.75 : 1))
      var runsPlaced = 0
      var liftsPlaced = 0
      for (index, day) in days.enumerated() {
        let wantsRun = index.isMultiple(of: 2) || index == days.count - 1
        let run = runsPlaced < runCount && (wantsRun || liftsPlaced >= strengthCount)
        if run {
          let longRun = runsPlaced == runCount - 1 && runCount > 1
          let share = runCount > 1 ? (longRun ? 0.4 : 0.6 / Double(runCount - 1)) : 1
          let meters = max(500, Int(Double(totalMeters) * share / 100) * 100)
          let minutes = min(profile.sessionMinutes, max(15, Int(Double(meters) / 150)))
          let cappedMeters = min(meters, minutes * 150)
          workouts.append(TrainingWorkout(
            date: day, kind: .run, title: longRun ? "Long easy run" : "Aerobic base",
            purpose: longRun ? "Build time on your feet at a conversational effort. Keep enough in reserve for your next strength session." : "Build your aerobic base without adding unnecessary fatigue to the week.",
            minutes: minutes, distanceMeters: cappedMeters,
            effort: "Conversational · RPE 3–4", isKey: longRun,
            segments: [
              RunSegment(title: "Ease in", seconds: 5 * 60, cue: "Start gently; settle into your rhythm.", phase: .warmUp),
              RunSegment(title: "Easy running", seconds: max(1, minutes - 10) * 60, cue: "A pace where you can speak in full sentences.", phase: .easy),
              RunSegment(title: "Cool down", seconds: 5 * 60, cue: "Gradually ease the pace.", phase: .coolDown)
            ]))
          runsPlaced += 1
        } else {
          let lower = liftsPlaced == 0
          workouts.append(strengthWorkout(on: day, lower: lower, minutes: profile.sessionMinutes, goal: profile.strengthGoal))
          liftsPlaced += 1
        }
      }
    }
    return TrainingPlan(basePlanID: basePlanID, reason: "Starter block accepted", profile: profile, workouts: workouts)
  }

  static func strengthWorkout(on date: Date, lower: Bool, minutes: Int, goal: StrengthGoal) -> TrainingWorkout {
    let reps = goal == .muscle ? 10 : 6
    let count = minutes < 40 ? 2 : 3
    let names = lower ? ["Goblet squat", "Romanian deadlift", "Reverse lunge", "Standing calf raise"] : ["Dumbbell bench press", "One-arm dumbbell row", "Seated shoulder press", "Lat pulldown"]
    return TrainingWorkout(
      date: date, kind: .strength, title: lower ? "Lower body" : "Upper body",
      purpose: lower ? "Build a strong foundation. Use a comfortable load and keep three reps in reserve." : "Build upper-body strength while giving your legs space to recover for the next run.",
      minutes: min(minutes, 50), effort: "Controlled · 3 RIR", isKey: lower,
      exercises: names.map { name in
        ExercisePrescription(name: name, note: "Choose a load that leaves 3 reps in reserve.", sets: (0..<count).map { _ in SetPrescription(reps: reps) })
      })
  }

  static func moving(_ workout: TrainingWorkout, to date: Date, in plan: TrainingPlan) -> TrainingPlan {
    var next = plan
    next.id = UUID()
    next.basePlanID = plan.id
    next.createdAt = Date()
    next.reason = "Moved \(workout.title) to \(date.formatted(date: .abbreviated, time: .omitted))"
    next.workouts = plan.workouts.map { old in
      var new = old.reidentified()
      if new.logicalID == workout.logicalID { new.date = Calendar.current.startOfDay(for: date) }
      return new
    }
    return next
  }

  static func conflicts(for workout: TrainingWorkout, on day: Date, in plan: TrainingPlan) -> [String] {
    plan.workouts.filter { $0.logicalID != workout.logicalID }.compactMap { other in
      let gap = abs(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: day), to: other.date).day ?? 99)
      if gap == 0 { return "This day already has \(other.title.lowercased()). Consider the combined duration before moving." }
      if gap <= 1 && workout.isKey && other.isKey && workout.kind != other.kind {
        return "\(other.title) is within a day. Lower-body fatigue may affect your key run."
      }
      return nil
    }
  }
}
