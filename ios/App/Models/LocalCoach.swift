import Foundation

enum LocalCoach {
  static func reply(to question: String, state: TrainingState) -> String {
    let query = question.lowercased()
    let profile = state.profile
    let workouts = state.plans.last?.workouts ?? []
    let completed = state.results.filter { $0.status != .skipped }
    if query.contains("pain") || query.contains("injur") {
      return "I can help explain your schedule, but I can’t assess pain or an injury. Avoid pushing through painful movement and seek advice from a qualified clinician. You can skip a session from its details; it won’t be added on top of tomorrow’s training."
    }
    if query.contains("tired") || query.contains("fatigue") || query.contains("miss") {
      return "You don’t need to make up every missed session. Your plan combines running and lifting, so adding extra work can crowd recovery. Open a session in Plan to skip it or review a move. You’ll see any nearby key-session conflicts before accepting. No changes have been made."
    }
    if query.contains("progress") || query.contains("done") {
      let meters = completed.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
      let lifts = completed.filter { $0.kind == .strength }.count
      return completed.isEmpty ? "There are no completed sessions yet. Log your first run or strength session and Progress will show your actual distance, completed sets, and consistency. Sample prescriptions don’t count as completed training." : "You’ve logged \(completed.count) sessions: \(profile.trainingUnits.distanceText(Double(meters))) of running and \(lifts) strength sessions. These totals reflect your saved results. A longer history is needed to assess a trend."
    }
    if query.contains("why") || query.contains("week") || query.contains("balance") || query.contains("plan") {
      let start = TrainingEngine.startOfWeek(containing: Date())
      let week = workouts.filter { $0.date >= start && $0.date < TrainingEngine.date(start, offset: 7) }
      let runs = week.filter { $0.kind == .run }.count
      let lifts = week.filter { $0.kind == .strength }.count
      return "This week has \(runs) runs and \(lifts) strength sessions. Easy runs support your aerobic base; upper-body days limit extra leg fatigue. Your goals are \(profile.runningGoal.rawValue.lowercased()) and \(profile.strengthGoal.rawValue.lowercased()). This starter block holds volume steady for three weeks, then reduces running in week four. It isn’t a race-specific or adaptive plan yet."
    }
    return "I can explain this week, summarize logged progress, or help you think through a missed session using the data on this phone. Try “Why is my week arranged this way?” Cloud AI isn’t connected in this build, so I won’t invent an answer or change your plan."
  }
}
