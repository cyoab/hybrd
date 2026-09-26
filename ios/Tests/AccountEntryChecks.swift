import Foundation

@MainActor enum AccountEntryChecks {
  static func run() throws {
    let empty = TrainingState.empty()
    precondition(empty.profile.name.isEmpty && empty.profile.weeklyKilometers == 0 && !empty.profile.isSample)
    precondition(empty.plans.flatMap(\.workouts).isEmpty && empty.results.isEmpty && empty.drafts.isEmpty && empty.messages.isEmpty)
    let sample = TrainingState.sample()
    let pristine = LegacyTrainingArchive(id: "legacy", payload: try JSONEncoder().encode(sample))
    precondition(!pristine.containsUserContent)
    var recorded = sample
    let workout = sample.plans[0].workouts[0]
    recorded.results = [WorkoutResult(plannedWorkoutID: workout.id, logicalWorkoutID: workout.logicalID,
      kind: .run, status: .completed, durationSeconds: 1200, distanceMeters: 3000, effort: 0, notes: "", sets: [])]
    recorded.drafts = [WorkoutDraft(workout: workout)]
    let payload = try JSONEncoder().encode(recorded)
    let archive = LegacyTrainingArchive(id: "legacy", payload: payload)
    precondition(archive.containsUserContent && archive.payload == payload)
    precondition(archive.state?.results == recorded.results && archive.state?.drafts == recorded.drafts)
    precondition(Data(archive.exportText.utf8) == payload)
    precondition(LegacyTrainingArchive(id: "damaged", payload: Data("unreadable".utf8)).containsUserContent)
    let legacyWatch = CompanionSnapshot(name: "Demo", isSample: true, workouts: sample.plans[0].workouts)
    let decoded = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONEncoder().encode(legacyWatch))
    precondition(!decoded.hasAccountPlan)
    let signedOut = CompanionSnapshot.signedOut()
    precondition(!signedOut.hasAccountPlan && signedOut.workouts.isEmpty)
    var linked = CompanionSnapshot(name: "Athlete", isSample: false, workouts: [], athleteID: UUID())
    precondition(linked.hasAccountPlan)
    linked.accountSignedOut = true; precondition(!linked.hasAccountPlan)
    print("PASS: empty account state, demo fixture exclusion, lossless local recording archive and account-scoped Watch snapshots")
  }
}
