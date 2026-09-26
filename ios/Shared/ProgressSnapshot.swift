import Foundation

/// Immutable, actual-only read model. Rule version 1; see docs/progress-metrics-handoff.md.
struct ProgressSnapshot {
  var period: ProgressPeriod
  var asOf: Date
  var start: Date
  var current: Totals
  var previous: Totals
  var lifetime: Totals
  var days: [Day]
  var rhythm: [Day]
  var milestones: [ProgressMilestone]
  var comparisons: [ProgressComparison]
  var results: [WorkoutResult]
  var workoutTitles: [UUID: String]

  var level: Int { lifetime.activeDays / 10 + 1 }
  var levelSteps: Int { lifetime.activeDays % 10 }
  var nextLevelIn: Int { 10 - levelSteps }
  var levelTitle: String {
    switch level {
    case 1: L10n.text("First steps")
    case 2: L10n.text("Finding rhythm")
    case 3: L10n.text("Building momentum")
    case 4: L10n.text("Showing up")
    case 5: L10n.text("In your stride")
    default: L10n.text("The long game")
    }
  }
  var latestMilestone: ProgressMilestone? {
    milestones.filter(\.earned).max { ($0.earnedAt ?? .distantPast) < ($1.earnedAt ?? .distantPast) }
  }
  var buckets: [Day] {
    guard period != .week else { return days }
    return stride(from: 0, to: days.count, by: 7).map { index in
      let group = days[index..<min(days.count, index + 7)]
      return Day(date: days[index].date, runMeters: group.reduce(0) { $0 + $1.runMeters },
        strengthSets: group.reduce(0) { $0 + $1.strengthSets },
        runSeconds: group.reduce(0) { $0 + $1.runSeconds }, liftSeconds: group.reduce(0) { $0 + $1.liftSeconds },
        results: group.flatMap(\.results))
    }
  }

  init(results input: [WorkoutResult], plans: [TrainingPlan], period: ProgressPeriod, now: Date = Date(), calendar: Calendar = .current) {
    self.period = period
    asOf = now
    let today = calendar.startOfDay(for: now)
    let start = calendar.date(byAdding: .day, value: -(period.rawValue - 1), to: today)!
    self.start = start
    let previousStart = calendar.date(byAdding: .day, value: -period.rawValue, to: start)!
    // Current canonical result wins for duplicated record IDs; latest logical result wins across plan versions.
    var byID: [UUID: WorkoutResult] = [:]
    for result in input where result.completedAt <= now { byID[result.id] = result }
    var byLogicalID: [UUID: WorkoutResult] = [:]
    for result in byID.values.sorted(by: Self.ordered) { byLogicalID[result.logicalWorkoutID] = result }
    let results = byLogicalID.values.filter(Self.isActual).sorted(by: Self.ordered)
    self.results = results.reversed()
    var prescriptions: [UUID: TrainingWorkout] = [:]
    for plan in plans { for workout in plan.workouts { prescriptions[workout.id] = workout } }
    workoutTitles = prescriptions.mapValues(\.title)
    var byDay: [Date: Day] = [:]
    var runningTotal = Totals()
    var activeDates: Set<Date> = []
    var disciplines: Set<WorkoutKind> = []
    var earned: [ProgressMilestone.Kind: Date] = [:]
    for result in results {
      let date = calendar.startOfDay(for: result.completedAt)
      activeDates.insert(date)
      disciplines.insert(result.kind)
      let sets = Self.validSets(result)
      let meters = result.kind == .run ? (result.distanceMeters ?? 0) : 0
      runningTotal.sessions += 1
      runningTotal.runMeters += meters
      runningTotal.strengthSets += sets.count
      runningTotal.seconds += max(0, result.durationSeconds)
      runningTotal.activeDays = activeDates.count
      runningTotal.runSessions += result.kind == .run ? 1 : 0
      runningTotal.liftSessions += result.kind == .strength ? 1 : 0
      var day = byDay[date] ?? Day(date: date)
      day.runMeters += meters
      day.strengthSets += sets.count
      if result.kind == .run { day.runSeconds += max(0, result.durationSeconds) }
      else { day.liftSeconds += max(0, result.durationSeconds) }
      day.results.append(result)
      byDay[date] = day
      for kind in ProgressMilestone.Kind.allCases where earned[kind] == nil {
        if Self.value(for: kind, totals: runningTotal, disciplines: disciplines.count) >= kind.target {
          earned[kind] = result.completedAt
        }
      }
    }
    lifetime = runningTotal
    milestones = ProgressMilestone.Kind.allCases.map { kind in
      ProgressMilestone(kind: kind, value: Self.value(for: kind, totals: runningTotal, disciplines: disciplines.count), earnedAt: earned[kind])
    }
    func makeDays(start: Date, count: Int) -> [Day] {
      (0..<count).map { offset in
        let date = calendar.date(byAdding: .day, value: offset, to: start)!
        return byDay[date] ?? Day(date: date)
      }
    }
    days = makeDays(start: start, count: period.rawValue)
    rhythm = makeDays(start: calendar.date(byAdding: .day, value: -27, to: today)!, count: 28)
    current = Self.totals(days)
    previous = Self.totals(makeDays(start: previousStart, count: period.rawValue))
    comparisons = Self.comparisons(results: results, prescriptions: prescriptions, calendar: calendar)
  }

  static func validSets(_ result: WorkoutResult) -> [LoggedSet] {
    guard result.kind == .strength && result.status != .skipped else { return [] }
    var seen: Set<UUID> = []
    return result.sets.filter {
      $0.isComplete && !$0.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      $0.kilograms.isFinite && (0...1_000).contains($0.kilograms) && (1...100).contains($0.reps) && seen.insert($0.id).inserted
    }
  }
  private static func isActual(_ result: WorkoutResult) -> Bool {
    guard result.status != .skipped else { return false }
    return result.kind == .run ? (result.distanceMeters ?? 0) > 0 && result.durationSeconds > 0 : !validSets(result).isEmpty
  }
  private static func ordered(_ a: WorkoutResult, _ b: WorkoutResult) -> Bool {
    a.completedAt == b.completedAt ? a.id.uuidString < b.id.uuidString : a.completedAt < b.completedAt
  }
  private static func totals(_ days: [Day]) -> Totals {
    Totals(sessions: days.reduce(0) { $0 + $1.results.count }, runMeters: days.reduce(0) { $0 + $1.runMeters },
      strengthSets: days.reduce(0) { $0 + $1.strengthSets }, seconds: days.reduce(0) { $0 + $1.runSeconds + $1.liftSeconds },
      activeDays: days.filter { !$0.results.isEmpty }.count,
      runSessions: days.flatMap(\.results).filter { $0.kind == .run }.count,
      liftSessions: days.flatMap(\.results).filter { $0.kind == .strength }.count)
  }
  private static func value(for kind: ProgressMilestone.Kind, totals: Totals, disciplines: Int) -> Int {
    switch kind {
    case .firstDay, .tenDays, .fiftyDays: totals.activeDays
    case .bothDisciplines: disciplines
    case .tenKilometers, .fiftyKilometers: totals.runMeters
    case .twentyFiveSets, .hundredSets: totals.strengthSets
    }
  }
  private static func comparisons(results: [WorkoutResult], prescriptions: [UUID: TrainingWorkout], calendar: Calendar) -> [ProgressComparison] {
    struct RunKey: Hashable { var meters: Int; var type: RunWorkoutType }
    struct LiftKey: Hashable { var name: String; var reps: Int }
    var runs: [RunKey: [ProgressComparison.Point]] = [:]
    var lifts: [LiftKey: [ProgressComparison.Point]] = [:]
    for result in results {
      if result.kind == .run, result.status == .completed, let meters = result.distanceMeters, meters >= 1_000 {
        let key = RunKey(meters: meters, type: prescriptions[result.plannedWorkoutID]?.resolvedRunType ?? .custom)
        runs[key, default: []].append(.init(resultID: result.id, date: result.completedAt, value: Double(result.durationSeconds) * 1_000 / Double(meters)))
      } else if result.kind == .strength {
        let grouped = Dictionary(grouping: validSets(result).filter { $0.loadConvention == nil || $0.loadConvention == .external }, by: { LiftKey(name: $0.exerciseName, reps: $0.reps) })
        for (key, sets) in grouped {
          lifts[key, default: []].append(.init(resultID: result.id, date: result.completedAt, value: sets.map(\.kilograms).max() ?? 0))
        }
      }
    }
    func comparable(_ points: [ProgressComparison.Point]) -> Bool {
      points.count >= 2 && !calendar.isDate(points.first!.date, inSameDayAs: points.last!.date)
    }
    let running = runs.compactMap { key, points -> ProgressComparison? in
      guard comparable(points) else { return nil }
      return ProgressComparison(kind: .run,
        title: "\((Double(key.meters) / 1_000).formatted(.number.precision(.fractionLength(0...3)))) km · \(key.type.title)",
        subtitle: L10n.text("Same distance & run type"), points: points, runDistanceMeters: key.meters, runType: key.type)
    }.sorted {
      $0.latestDate == $1.latestDate ? $0.title < $1.title : $0.latestDate > $1.latestDate
    }.first
    let lifting = lifts.compactMap { key, points -> ProgressComparison? in
      guard comparable(points) else { return nil }
      return ProgressComparison(kind: .strength, title: key.name, subtitle: L10n.text("Same lift · \(key.reps) reps"), points: points)
    }.sorted {
      $0.latestDate == $1.latestDate ? $0.title + $0.subtitle < $1.title + $1.subtitle : $0.latestDate > $1.latestDate
    }.first
    return [running, lifting].compactMap { $0 }
  }

  struct Totals {
    var sessions = 0
    var runMeters = 0
    var strengthSets = 0
    var seconds = 0
    var activeDays = 0
    var runSessions = 0
    var liftSessions = 0
  }
  struct Day: Identifiable {
    var date: Date
    var runMeters = 0
    var strengthSets = 0
    var runSeconds = 0
    var liftSeconds = 0
    var results: [WorkoutResult] = []
    var id: Date { date }
  }
}
