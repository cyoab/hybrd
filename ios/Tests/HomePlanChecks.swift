import Foundation

enum HomePlanChecks {
  static func run() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // Sunday remains Sunday when a week contains a 23-hour or 25-hour day.
    for sunday in [date(2026, 3, 1), date(2026, 3, 8), date(2026, 10, 25), date(2026, 11, 1)] {
      let window = TrainingWeekWindow(containing: sunday, calendar: calendar)
      let nextWeek = window.addingDays(7, to: window.startOfWeek(containing: sunday))
      let nextSelection = window.selection(in: nextWeek, matching: sunday)
      precondition(calendar.component(.weekday, from: nextSelection) == 1)
      precondition(calendar.component(.hour, from: nextSelection) == 0)
      precondition(calendar.dateComponents([.day], from: sunday, to: nextSelection).day == 7)
      let restored = window.selection(in: window.startOfWeek(containing: sunday), matching: nextSelection)
      precondition(restored == sunday, "Backward paging must restore the original local date")
    }

    let wednesday = date(2026, 12, 30)
    var window = TrainingWeekWindow(containing: wednesday, calendar: calendar)
    let next = window.selection(in: window.addingDays(7, to: wednesday), matching: wednesday)
    precondition(next == date(2027, 1, 6), "Weekday selection must cross the year boundary")
    precondition(calendar.component(.weekday, from: window.weeks[0]) == 2,
      "The training calendar must stay Monday-first")
    let initialWeeks = window.weeks
    window.reveal(initialWeeks[0])
    precondition(Set(initialWeeks).isSubset(of: Set(window.weeks)), "Prepending must preserve page IDs")
    window.reveal(window.weeks.last!)
    precondition(Set(initialWeeks).isSubset(of: Set(window.weeks)), "Appending must preserve page IDs")
    precondition(window.weeks.count == Set(window.weeks).count)
    for (left, right) in zip(window.weeks, window.weeks.dropFirst()) {
      precondition(calendar.dateComponents([.day], from: left, to: right).day == 7,
        "Paging windows must not skip or repeat weeks")
    }
    for jump in [date(1990, 2, 11), date(2050, 7, 17), Date()] {
      window.reveal(jump)
      precondition(window.weeks.contains(window.startOfWeek(containing: jump)))
      precondition(window.weeks.count == 17, "Distant jumps must reset the window instead of allocating decades")
    }

    let plan = SampleTraining.makePlan(profile: TrainingProfile())
    let run = plan.workouts.first { $0.kind == .run }!
    let lift = plan.workouts.first { $0.kind == .strength }!
    let empty = WeeklyTrainingSummary(workouts: [run, lift], results: [])
    precondition(empty.loggedMeters == 0 && empty.loggedLifts == 0,
      "Sample prescriptions must never look like completed activity")
    let runResult = WorkoutResult(plannedWorkoutID: UUID(), logicalWorkoutID: run.logicalID,
      kind: .run, status: .completed, durationSeconds: 1_800, distanceMeters: run.distanceMeters / 2,
      effort: 5, notes: "", sets: [])
    let partialLift = WorkoutResult(plannedWorkoutID: lift.id, logicalWorkoutID: lift.logicalID,
      kind: .strength, status: .partial, durationSeconds: 600, effort: 5, notes: "", sets: [])
    var outsideWeek = runResult
    outsideWeek.logicalWorkoutID = UUID()
    outsideWeek.distanceMeters = 99_000
    let summary = WeeklyTrainingSummary(workouts: [run, lift], results: [runResult, partialLift, outsideWeek])
    precondition(summary.loggedMeters == run.distanceMeters / 2 && summary.runningProgress == 0.5,
      "Match results by logical ID, including after a plan revision, and exclude other weeks")
    precondition(summary.loggedLifts == 1 && summary.liftingProgress == 1,
      "Partial sessions count as logged, not as fully completed")
    var skipped = runResult
    skipped.status = .skipped
    var skippedLift = partialLift
    skippedLift.status = .skipped
    let skippedSummary = WeeklyTrainingSummary(workouts: [run, lift], results: [skipped, skippedLift])
    precondition(skippedSummary.loggedMeters == 0 && skippedSummary.loggedLifts == 0)
    var beyondTarget = runResult
    beyondTarget.distanceMeters = run.distanceMeters + 1_000
    let exceeded = WeeklyTrainingSummary(workouts: [run], results: [beyondTarget])
    precondition(exceeded.runningProgress == 1 && exceeded.loggedMeters == run.distanceMeters + 1_000,
      "Clamp the ring, not the actual distance")
    let noPlan = WeeklyTrainingSummary(workouts: [], results: [runResult])
    precondition(noPlan.runningProgress == 0 && noPlan.liftingProgress == 0)
    print("PASS: home week paging across DST and year boundaries, window extension and date jumps, actual/planned totals and zero/over-target rings")
  }
}
