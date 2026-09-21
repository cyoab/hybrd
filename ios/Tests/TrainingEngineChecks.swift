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
    precondition(draft.sets.map(\.prescriptionID) == lift.exercises.flatMap(\.sets).map(\.id))

    let restored = try JSONDecoder().decode(TrainingPlan.self, from: JSONEncoder().encode(moved))
    precondition(restored.id == moved.id && restored.workouts == moved.workouts)
    print("PASS: availability, stable identities, immutable snapshots, conflict checks, result separation, and encoding")
  }
}
