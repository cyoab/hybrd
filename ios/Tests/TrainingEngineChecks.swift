import Foundation

@main
enum TrainingEngineChecks {
  static func main() throws {
    var profile = TrainingProfile()
    profile.availableDays = [2, 4, 6]
    profile.strengthDays = 2
    let start = ISO8601DateFormatter().date(from: "2026-09-21T12:00:00Z")!
    let plan = TrainingEngine.makePlan(profile: profile, start: start)
    precondition(plan.workouts.count == 12, "Four weeks must respect three available days")
    precondition(plan.workouts.allSatisfy {
      profile.availableDays.contains(Calendar.current.component(.weekday, from: $0.date))
    }, "Never schedule on unavailable days")
    precondition(Set(plan.workouts.map(\.id)).count == plan.workouts.count)
    precondition(Set(plan.workouts.map(\.logicalID)).count == plan.workouts.count)

    let original = plan.workouts[0]
    let moved = TrainingEngine.moving(original, to: TrainingEngine.date(start, offset: 1), in: plan)
    precondition(moved.id != plan.id && moved.basePlanID == plan.id)
    precondition(moved.workouts.map(\.logicalID) == plan.workouts.map(\.logicalID), "Logical identities survive plan revisions")
    precondition(Set(moved.workouts.map(\.id)).isDisjoint(with: Set(plan.workouts.map(\.id))), "Physical prescription IDs must be new")
    precondition(plan.workouts[0].date == original.date, "Moving must not mutate historical snapshots")
    let originalSetIDs = Set(plan.workouts.flatMap(\.exercises).flatMap(\.sets).map(\.id))
    let movedSetIDs = Set(moved.workouts.flatMap(\.exercises).flatMap(\.sets).map(\.id))
    precondition(originalSetIDs.isDisjoint(with: movedSetIDs), "Nested prescriptions must also get new IDs")
    precondition(!TrainingEngine.conflicts(for: original, on: plan.workouts[1].date, in: plan).isEmpty)

    let runDraft = WorkoutDraft(workout: original)
    precondition(runDraft.distanceKilometers == 0 && runDraft.durationMinutes == 0, "Prescriptions are not actual results")
    let lift = plan.workouts.first { $0.kind == .strength }!
    let draft = WorkoutDraft(workout: lift)
    precondition(draft.sets.allSatisfy { !$0.isComplete }, "No sets are performed by default")
    precondition(draft.sets.compactMap(\.prescriptionID) == lift.exercises.flatMap(\.sets).map(\.id))

    var logged = draft
    logged.resume(at: start)
    logged.pause(at: start.addingTimeInterval(60))
    logged.resume(at: start.addingTimeInterval(600))
    logged.pause(at: start.addingTimeInterval(630))
    precondition(logged.activeSeconds() == 90, "Paused time must not count as performed work")
    for index in logged.sets.indices { logged.sets[index].isComplete = true }
    precondition(logged.canFinish && logged.hasAllPrescribedSets)
    logged.sets.removeFirst()
    precondition(logged.canFinish && !logged.hasAllPrescribedSets, "Removed prescribed sets make a session partial")
    let count = logged.sets.count
    logged.addSet(for: lift.exercises[0])
    precondition(logged.sets.count == count + 1 && logged.sets.last?.prescriptionID == nil)
    precondition(logged.sets.last?.isComplete == false, "Extra sets require explicit completion")
    logged.sets[0].kilograms = -1
    precondition(!logged.canFinish, "Negative completed loads must be rejected")

    var runLog = runDraft
    runLog.distanceKilometers = 0.000001
    runLog.durationMinutes = 30
    precondition(!runLog.canFinish, "A run must contain at least one meter of actual distance")
    runLog.distanceKilometers = 5
    precondition(runLog.canFinish)
    var legacyDraft = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
    legacyDraft.removeValue(forKey: "elapsedSeconds")
    legacyDraft.removeValue(forKey: "runningSince")
    let restoredDraft = try JSONDecoder().decode(WorkoutDraft.self, from: JSONSerialization.data(withJSONObject: legacyDraft))
    precondition(restoredDraft.sets == draft.sets && restoredDraft.activeSeconds() == 0)

    let restored = try JSONDecoder().decode(TrainingPlan.self, from: JSONEncoder().encode(moved))
    precondition(restored.id == moved.id && restored.workouts == moved.workouts)
    // Optional presentation metadata must not break existing persisted training.
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
    legacy.removeValue(forKey: "scheduledMinutes")
    legacy.removeValue(forKey: "isOptional")
    let legacyWorkout = try JSONDecoder().decode(TrainingWorkout.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(legacyWorkout.id == original.id && legacyWorkout.scheduledMinutes == nil)
    let sample = SampleTraining.makePlan(profile: profile, start: start)
    precondition(sample.workouts.filter { $0.kind == .run }.allSatisfy {
      $0.segments.reduce(0) { $0 + $1.totalSeconds } == $0.minutes * 60
    }, "Displayed interval totals must equal prescribed duration")
    precondition(sample.workouts.contains { $0.isOptional == true })
    print("PASS: planning invariants, legacy decoding, interval totals, actual-result validation, partial/extra sets, and pause/resume timing")
  }
}
