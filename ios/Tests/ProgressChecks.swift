import Foundation

enum ProgressChecks {
  static func run() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let now = ISO8601DateFormatter().date(from: "2026-03-10T16:00:00Z")!
    func date(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }
    func run(_ offset: Int, meters: Int = 5_000, seconds: Int = 1_800) -> WorkoutResult {
      WorkoutResult(plannedWorkoutID: UUID(), logicalWorkoutID: UUID(), completedAt: date(offset),
        kind: .run, status: .completed, durationSeconds: seconds, distanceMeters: meters, effort: 5, notes: "", sets: [])
    }
    func lift(_ offset: Int, name: String = "Bench press", reps: Int = 5, kg: Double = 50, count: Int = 3) -> WorkoutResult {
      WorkoutResult(plannedWorkoutID: UUID(), logicalWorkoutID: UUID(), completedAt: date(offset),
        kind: .strength, status: .partial, durationSeconds: 600, effort: 5, notes: "",
        sets: (0..<count).map { _ in LoggedSet(exerciseName: name, reps: reps, kilograms: kg, isComplete: true) })
    }
    func snapshot(_ results: [WorkoutResult], _ period: ProgressPeriod = .month, plans: [TrainingPlan] = [], at: Date? = nil) -> ProgressSnapshot {
      ProgressSnapshot(results: results, plans: plans, period: period, now: at ?? now, calendar: calendar)
    }
    let empty = snapshot([])
    precondition(empty.lifetime.sessions == 0 && empty.days.count == 28 && empty.rhythm.count == 28)
    precondition(empty.level == 1 && empty.levelSteps == 0 && empty.milestones.allSatisfy { !$0.earned })
    precondition(empty.comparisons.isEmpty && empty.buckets.count == 4)

    var skipped = run(-1); skipped.status = .skipped
    var draftSets = lift(-2); draftSets.sets[0].isComplete = false
    let repeatedSet = draftSets.sets[1]
    draftSets.sets += [repeatedSet, LoggedSet(exerciseName: "", reps: 5, kilograms: 10, isComplete: true),
      LoggedSet(exerciseName: "Squat", reps: 0, kilograms: 10, isComplete: true),
      LoggedSet(exerciseName: "Squat", reps: 5, kilograms: .infinity, isComplete: true),
      LoggedSet(exerciseName: "Squat", reps: 5, kilograms: -1, isComplete: true)]
    let validPartial = snapshot([skipped, draftSets, run(1), run(0, meters: 0), run(0, seconds: 0)])
    precondition(validPartial.current.sessions == 1 && validPartial.current.strengthSets == 2)
    precondition(validPartial.current.runMeters == 0 && validPartial.lifetime.activeDays == 1)
    precondition(ProgressSnapshot.validSets(skipped).isEmpty)
    precondition(snapshot([lift(0, kg: 0)]).current.strengthSets == 3, "Bodyweight sets count")

    let first = run(-3)
    var corrected = first; corrected.distanceMeters = 2_000
    let deduped = snapshot([first, corrected])
    precondition(deduped.current.sessions == 1 && deduped.current.runMeters == 2_000)
    var replanned = run(-1); replanned.logicalWorkoutID = first.logicalWorkoutID
    precondition(snapshot([first, replanned]).current.sessions == 1, "Plan versions cannot duplicate actual work")
    replanned.status = .skipped
    precondition(snapshot([first, replanned]).current.sessions == 0, "Latest logical result can revoke old activity")

    let both = snapshot([run(0), lift(0)])
    precondition(both.lifetime.activeDays == 1 && both.lifetime.sessions == 2)
    precondition(both.levelSteps == 1 && both.milestones.first { $0.kind == .bothDisciplines }!.earned)
    let tenDays = (-19 ... -10).map { run($0) }
    let rested = snapshot(tenDays)
    precondition(rested.level == 2 && rested.levelSteps == 0 && rested.nextLevelIn == 10)
    precondition(rested.milestones.first { $0.kind == .tenDays }!.earnedAt == date(-10))
    precondition(rested.milestones.first { $0.kind == .tenKilometers }!.earnedAt == date(-18))
    precondition(rested.milestones.first { $0.kind == .fiftyKilometers }!.earned)
    precondition(!snapshot(Array(tenDays.dropLast())).milestones.first { $0.kind == .fiftyKilometers }!.earned)
    precondition(snapshot([lift(-2, count: 24), lift(-1, count: 1)]).milestones.first { $0.kind == .twentyFiveSets }!.earnedAt == date(-1))
    precondition(rested.latestMilestone != nil)

    let daily = (-170...0).map { run($0, meters: 1_000, seconds: 360) }
    for period in ProgressPeriod.allCases {
      let value = snapshot(daily, period)
      precondition(value.current.sessions == period.rawValue && value.previous.sessions == period.rawValue)
      precondition(value.current.runMeters == period.rawValue * 1_000 && value.previous.runMeters == period.rawValue * 1_000)
      precondition(value.days.count == period.rawValue && value.rhythm.count == 28 && value.lifetime.activeDays == 171)
      precondition(value.buckets.reduce(0) { $0 + $1.runMeters } == value.current.runMeters)
      precondition(value.buckets.reduce(0) { $0 + $1.results.count } == value.current.sessions)
      precondition(Set(value.days.map(\.date)).count == period.rawValue)
      precondition(value.days.allSatisfy { calendar.component(.hour, from: $0.date) == 0 })
    }
    let dst = snapshot(daily, .week)
    precondition(zip(dst.days, dst.days.dropFirst()).contains { $1.date.timeIntervalSince($0.date) == 23 * 3_600 }, "Days must follow the calendar across DST")
    let newYear = ISO8601DateFormatter().date(from: "2027-01-02T17:00:00Z")!
    let year = snapshot([], .week, at: newYear)
    precondition(calendar.component(.year, from: year.start) == 2026)
    var midnightBefore = run(0)
    midnightBefore.completedAt = calendar.startOfDay(for: now).addingTimeInterval(-1)
    var midnightAfter = run(0)
    midnightAfter.completedAt = calendar.startOfDay(for: now)
    let midnight = snapshot([midnightBefore, midnightAfter])
    precondition(midnight.lifetime.activeDays == 2 && midnight.days.last!.results.count == 1)

    let faster = snapshot([run(-5), run(0, seconds: 1_500)])
    precondition(faster.comparisons.count == 1 && faster.comparisons[0].changeLabel == "60 sec/km faster")
    precondition(faster.comparisons[0].best.value == 300)
    precondition(snapshot([run(-5), run(0, meters: 5_001)]).comparisons.isEmpty, "Never normalize dissimilar distances into a PR")
    precondition(snapshot([run(0), run(0, seconds: 1_500)]).comparisons.isEmpty, "Same-day pairs are not progress over time")
    var partialRun = run(0); partialRun.status = .partial
    precondition(snapshot([run(-5), partialRun]).comparisons.isEmpty)
    var easy = RunWorkoutTemplate.easyThirty.workout(on: date(-5))
    var tempo = RunWorkoutTemplate.steadyTempo.workout(on: date(0))
    var a = run(-5); a.plannedWorkoutID = easy.id
    var b = run(0); b.plannedWorkoutID = tempo.id
    var plan = TrainingPlan(reason: "Test", profile: TrainingProfile(), workouts: [easy, tempo])
    precondition(snapshot([a, b], plans: [plan]).comparisons.isEmpty)
    tempo.runType = .easy; easy.title = "Easy"; plan.workouts = [easy, tempo]
    precondition(snapshot([a, b], plans: [plan]).comparisons[0].title.contains("Easy"))
    precondition(snapshot([lift(-2), lift(0, reps: 8)]).comparisons.isEmpty)
    precondition(snapshot([lift(-2), lift(0, name: "Incline bench press")]).comparisons.isEmpty)
    let stronger = snapshot([lift(-5), lift(-2, kg: 65), lift(0, kg: 60)])
    precondition(stronger.comparisons[0].changeLabel == "10 kg more" && stronger.comparisons[0].best.value == 65)
    precondition(snapshot([lift(-2), lift(0, kg: 40)]).comparisons[0].changeLabel == "10 kg less")
    let tied = [lift(-5, name: "Squat"), lift(-5), lift(0, name: "Squat"), lift(0)]
    precondition(snapshot(tied).comparisons[0].title == "Bench press")
    precondition(snapshot(tied.reversed()).comparisons[0].title == "Bench press", "Stable tie selection")
    let independentPeriods = snapshot(tenDays, .week)
    precondition(independentPeriods.current.sessions == 0 && independentPeriods.level == 2, "Range selection does not reset the lifetime journey")
    print("PASS: Progress actual-only totals, valid partial/bodyweight sets, deduplication and corrections, future/skipped exclusion, day-based levels, milestones, rest preservation, 7/28/84-day ranges, DST/year/midnight boundaries, exact effort matching, best values and deterministic comparisons")
  }
}
