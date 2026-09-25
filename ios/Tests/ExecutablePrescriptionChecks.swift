import Foundation

@MainActor enum ExecutablePrescriptionChecks {
  static func run() throws {
    let decoder = JSONDecoder()
    func data(_ file: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: "../contracts/fixtures/ai/" + file)) }
    let catalog = BackendWire.ExerciseCatalog(version: 1, exercises: [.init(id: UUID(uuidString: "30000000-0000-4000-8000-000000000091")!, slug: "press", name: "Renamed catalog press", unilateral: false, active: true, metadata: [:])], equipment: [], muscleGroups: [], aliases: [], exerciseMuscles: [], exerciseEquipment: [])
    let wire = try decoder.decode(BackendWire.PlannedWorkoutInput.self, from: data("mixed-run.json"))
    let planID = UUID()
    let workout = try BackendTrainingMapping.workout(wire, catalog: catalog, planVersionID: planID)
    let expectedIDs = try decoder.decode([UUID].self, from: data("mixed-run-execution-ids.json"))
    precondition(workout.segments.map(\.id) == expectedIDs && Set(expectedIDs).count == 8)
    precondition(workout.estimatedDurationSeconds == 1837 && workout.scheduledMinutes == 90 && workout.planVersionID == planID)
    precondition(workout.segments[1].targets?.paceMinSPerKm == 251.5 && workout.segments[1].targets?.rpeMin == 6.5)
    var upperOnly = workout.segments[1].targets!; upperOnly.hrMinBpm = nil
    precondition(upperOnly.summary(units: .metric).contains("≤ 172 bpm"), "Upper-only targets remain visible")
    precondition(workout.segments.last?.phase == .stride && workout.executionIssue == nil)
    precondition(workout.reidentified().executionIssue != nil, "An optimistic plan move must sync canonical IDs before execution")
    let snapshot = CompanionSnapshot(name: "Fixture", isSample: false, workouts: [workout], athleteID: UUID(), executableVersion: 2)
    let watch = try decoder.decode(CompanionSnapshot.self, from: JSONEncoder().encode(snapshot))
    precondition(watch.workouts == [workout], "Phone-to-Watch roundtrip retains all targets and identities")
    var invalid = wire
    if case .running(var value) = invalid { value.run.blocks[0].repeatCount = -1; invalid = .running(value) }
    do { _ = try BackendTrainingMapping.workout(invalid, catalog: catalog); preconditionFailure("Negative repeats must reject without a range trap") } catch {}
    var ambiguous = workout
    ambiguous.segments[0].targets?.distanceM = 100
    precondition(ambiguous.executionIssue != nil, "Combined end conditions have no defined v1 semantics")
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var recording = RunRecording(workout: workout, source: .watch, startedAt: start, runningSince: start, checkpointAt: start)
    recording.observeExecution(at: start.addingTimeInterval(60))
    precondition(recording.execution?.index == 1 && recording.meters == 0)
    recording.observeExecution(at: start.addingTimeInterval(1000))
    precondition(recording.execution?.index == 1, "No GPS means no distance completion, regardless of time")
    recording.updateDistance(390, at: 1001); recording.observeExecution(at: start.addingTimeInterval(1001))
    precondition(RunGuidance(run: recording, at: start.addingTimeInterval(1001)).remainingMeters == 10)
    recording.pause(at: start.addingTimeInterval(1002)); recording.observeExecution(at: start.addingTimeInterval(2000))
    precondition(recording.execution?.index == 1)
    recording.resume(at: start.addingTimeInterval(2000))
    recording.updateDistance(405, at: 1005); recording.observeExecution(at: start.addingTimeInterval(2003))
    precondition(recording.execution?.index == 2 && recording.execution?.events.last?.endMeters == 405)
    recording = try decoder.decode(RunRecording.self, from: JSONEncoder().encode(recording))
    precondition(recording.execution?.events.count == 2 && recording.workout.planVersionID == planID)
    let before = recording.meters
    recording.advanceStep(at: start.addingTimeInterval(2004))
    precondition(recording.execution?.index == 3 && recording.meters == before && recording.execution?.events.last?.reason == .manualAdvance)
    recording.finish(at: start.addingTimeInterval(2009))
    precondition(recording.execution?.events.last?.reason == .workoutFinished && recording.elapsed == 1011)

    let strengthWire = try decoder.decode(BackendWire.PlannedWorkoutInput.self, from: data("rich-strength.json"))
    let strength = try BackendTrainingMapping.workout(strengthWire, catalog: catalog, planVersionID: planID)
    precondition(strength.exercises[0].canonicalExerciseID == catalog.exercises[0].id)
    let sets = strength.exercises[0].sets
    precondition(sets[0].targets?.setKind == .warmup && sets[2].targets?.setKind == .backoff)
    precondition(sets[1].targets?.rirMin == 1.5 && sets[1].targets?.loadPercentE1rm == 72.5 && sets[1].targets?.restS == 120)
    precondition(strength.exercises[0].substitutions?.count == 1 && strength.exercises[0].supersetGroupID != nil)
    var draft = WorkoutDraft(workout: strength)
    precondition(draft.sets.allSatisfy { !$0.isComplete && $0.kilograms == 0 && $0.measuredRIR == nil })
    draft.sets[0].kilograms = 22.75; draft.sets[0].reps = 12; draft.sets[0].fractionalRIR = 2.5; draft.sets[0].isComplete = true
    draft.sets[0].loadConvention = .assistance; draft.sets[0].completedAt = start
    let result = WorkoutResult(plannedWorkoutID: strength.id, logicalWorkoutID: strength.logicalID, kind: .strength, status: .partial, durationSeconds: 30, effort: 0, notes: "", sets: [draft.sets[0]])
    precondition(LoggedStrengthRecords.candidates(from: [result]).isEmpty, "Assistance must not become an external-load PR")
    let state = TrainingState(profile: TrainingProfile(), plans: [TrainingPlan(id: planID, reason: "", profile: TrainingProfile(), workouts: [strength])])
    let mutation = try BackendTrainingMapping.resultMutation(result, state: state, catalog: catalog, knownPlans: [strength.id])
    let actual = try decoder.decode(BackendWire.WorkoutResultInputStrength.self, from: JSONEncoder().encode(mutation.payload))
    precondition(actual.exercises[0].exerciseId == catalog.exercises[0].id)
    precondition(actual.exercises[0].sets[0].rir == 2.5 && actual.exercises[0].sets[0].loadKg == 22.75 && actual.exercises[0].sets[0].loadConvention == .assistance)
    print("PASS: shared run/strength fixtures, deterministic repeat IDs, Watch parity, distance completion, pause/manual/finish events, canonical identity and fractional actuals")
  }
}
