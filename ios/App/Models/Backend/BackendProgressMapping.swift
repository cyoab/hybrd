import Foundation

enum BackendProgressMapping {
  static func apply(_ remote: BackendWire.ProgressSummary, to local: ProgressSnapshot) throws -> ProgressSnapshot {
    var s = local
    s.asOf = remote.asOf.date; s.start = try ConnectedDraftMapping.date(remote.range.startDate)
    s.current = totals(remote.totals.current); s.previous = totals(remote.totals.previous); s.lifetime = totals(remote.totals.lifetime)
    let days = Dictionary(grouping: local.results) { result in
      // Result drill-downs retain their canonical date rather than a newly inferred travel timezone.
      result.canonicalTrainingDate ?? (try? BackendDay(date: result.completedAt, timeZone: TimeZone(identifier: remote.timezone) ?? .current).rawValue) ?? ""
    }
    func day(_ v: BackendWire.ProgressDay) throws -> ProgressSnapshot.Day {
      .init(date: try ConnectedDraftMapping.date(v.date), runMeters: Int(v.runMeters), strengthSets: v.strengthSets,
        runSeconds: 0, liftSeconds: 0, results: days[v.date.rawValue] ?? [])
    }
    s.days = try remote.series.map(day); s.rhythm = try remote.activityDays.map(day)
    s.milestones = remote.milestones.compactMap { m in
      guard let kind = ProgressMilestone.Kind(rawValue: m.key) else { return nil }
      return ProgressMilestone(kind: kind, value: Int(m.current), earnedAt: m.earnedAt?.date)
    }
    s.comparisons = try remote.comparisons.map { c in
      let points = try c.chartPoints.map { p in ProgressComparison.Point(resultID: p.resultId, date: try ConnectedDraftMapping.date(p.trainingDate), value: p.value) }
      guard points.count >= 2 else { throw BackendContractError.invalidResponse }
      switch c.group {
      case .running(let g): return ProgressComparison(kind: .run, title: g.runType.rawValue, subtitle: "", points: points, runDistanceMeters: g.distanceM, runType: RunWorkoutType(rawValue: g.runType.rawValue))
      case .strength(let g): return ProgressComparison(kind: .strength, title: g.exerciseName, subtitle: "\(g.reps) reps · \(g.loadConvention.rawValue)", points: points)
      }
    }
    return s
  }
  private static func totals(_ v: BackendWire.ProgressTotals) -> ProgressSnapshot.Totals {
    .init(sessions: v.sessions, runMeters: Int(v.runMeters), strengthSets: v.strengthSets, seconds: Int(v.activeSeconds), activeDays: v.activeDays, runSessions: v.runSessions, liftSessions: v.liftSessions)
  }
}
