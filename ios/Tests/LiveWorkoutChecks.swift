import Foundation

enum LiveWorkoutChecks {
  static func run() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let workout = RunWorkoutTemplate.twoMinuteIntervals.workout(on: start)
    var run = RunRecording(workout: workout, zones: PersonalHeartRateZones(zone2: 120, zone3: 140, zone4: 160, zone5: 180), source: .watch, startedAt: start, runningSince: start, checkpointAt: start)
    precondition(run.meters == 0 && !run.canSave && run.currentHeartRate(at: start) == nil)
    run.pause(at: start.addingTimeInterval(60))
    precondition(run.seconds(at: start.addingTimeInterval(600)) == 60)
    run.resume(at: start.addingTimeInterval(600))
    precondition(run.seconds(at: start.addingTimeInterval(660)) == 120)
    run.pause(at: start.addingTimeInterval(660))
    run.resume(at: start.addingTimeInterval(700))
    let originalStep = run.step(at: start.addingTimeInterval(700))!
    run.advanceStep(at: start.addingTimeInterval(700))
    precondition(run.step(at: start.addingTimeInterval(700))!.id == originalStep.id + 1)
    precondition(run.seconds(at: start.addingTimeInterval(700)) == 120, "Skipping guidance never creates actual work")
    run.updateDistance(500, at: 150)
    run.updateDistance(2_500, at: 750)
    let kilometers = run.laps.filter { $0.kind == .kilometer }
    precondition(kilometers.count == 2 && kilometers.allSatisfy { abs($0.seconds - 300) < 0.001 })
    run.updateDistance(2_000, at: 800)
    run.updateDistance(.nan, at: 800)
    run.updateDistance(3_000, at: 700)
    precondition(run.meters == 2_500, "Distance never regresses or accepts invalid/out-of-order samples")
    run.markLap(at: start.addingTimeInterval(1_400))
    precondition(run.laps.filter { $0.kind == .manual }.count == 1)
    run.pause(at: start.addingTimeInterval(1_400))
    run.markLap(at: start.addingTimeInterval(1_500))
    precondition(run.laps.filter { $0.kind == .manual }.count == 1)
    run.heartRate = 145; run.heartRateAt = start.addingTimeInterval(1_400)
    precondition(run.currentHeartRate(at: start.addingTimeInterval(1_400)) == nil, "Paused readings are not live")
    run.resume(at: start.addingTimeInterval(1_400))
    precondition(run.currentHeartRate(at: start.addingTimeInterval(1_419)) == 145)
    precondition(run.currentHeartRate(at: start.addingTimeInterval(1_421)) == nil, "Stale HR is unavailable")
    precondition(run.zone(for: 119) == .one && run.zone(for: 120) == .two && run.zone(for: 180) == .five)
    run.finish(at: start.addingTimeInterval(1_450))
    precondition(run.isFinished && run.canSave && run.result().id == run.id && run.result().effort == 0)
    precondition(run.result().durationSeconds == 870 && run.result().distanceMeters == 2_500)
    precondition(run.result().plannedWorkoutID == workout.id && run.result().logicalWorkoutID == workout.logicalID)
    let roundTrip = try JSONDecoder().decode(RunRecording.self, from: JSONEncoder().encode(run))
    precondition(roundTrip == run && roundTrip.result().run == run)
    precondition(RunRecording.pace(nil) == "—" && RunRecording.clock(3_661) == "1:01:01")

    func point(_ seconds: Double, longitude: Double = 0, accuracy: Double = 5) -> RunLocation {
      RunLocation(latitude: 0, longitude: longitude, altitude: 0, accuracy: accuracy, timestamp: start.addingTimeInterval(seconds))
    }
    var gps = RunGPSFilter()
    precondition(gps.accept(point(0), now: start, after: start)!.point.startsSegment)
    precondition(gps.accept(point(1, longitude: 0.000001), now: start.addingTimeInterval(1), after: start) == nil, "Stationary jitter is excluded")
    precondition(gps.accept(point(2, longitude: 1), now: start.addingTimeInterval(2), after: start) == nil, "Teleport rejected")
    precondition(gps.accept(point(2, longitude: 0.00005, accuracy: 50), now: start.addingTimeInterval(2), after: start) == nil)
    let measured = gps.accept(point(2, longitude: 0.00005), now: start.addingTimeInterval(2), after: start)!
    precondition((5...6).contains(measured.meters) && !measured.point.startsSegment)
    precondition(gps.accept(point(1), now: start.addingTimeInterval(2), after: start) == nil)
    precondition(gps.accept(point(4), now: start.addingTimeInterval(20), after: start) == nil, "Stale fix rejected")
    let gap = gps.accept(point(30, longitude: 0.01), now: start.addingTimeInterval(30), after: start)!
    precondition(gap.point.startsSegment && gap.meters == 0, "Never bridge an outage")
    gps.reset()
    precondition(gps.accept(point(31, longitude: 0.02), now: start.addingTimeInterval(31), after: start)!.meters == 0, "Never count movement while paused")
    precondition(gps.accept(point(32, longitude: .nan), now: start.addingTimeInterval(32), after: start) == nil)

    let plan = TrainingEngine.makePlan(profile: TrainingProfile(), start: start)
    var draft = WorkoutDraft(workout: plan.workouts.first { $0.kind == .strength }!)
    draft.sets[0].isComplete = true; draft.sets[0].rir = 0
    precondition(draft.canFinish)
    draft.sets[0].rir = 11; precondition(!draft.canFinish)
    draft.sets[0].rir = -1; precondition(!draft.canFinish)
    draft.sets[0].rir = 10; precondition(draft.canFinish)
    draft.rest = StrengthRestTimer(duration: 90, endsAt: start.addingTimeInterval(90), exerciseName: "Squat")
    precondition(draft.rest!.remaining(at: start.addingTimeInterval(30)) == 60 && draft.rest!.remaining(at: start.addingTimeInterval(120)) == 0)
    let restored = try JSONDecoder().decode(WorkoutDraft.self, from: JSONEncoder().encode(draft))
    precondition(restored.rest == draft.rest && restored.sets[0].rir == 10)
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
    legacy.removeValue(forKey: "rest")
    var sets = legacy["sets"] as! [[String: Any]]
    for index in sets.indices { sets[index].removeValue(forKey: "rir") }
    legacy["sets"] = sets
    let oldDraft = try JSONDecoder().decode(WorkoutDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(oldDraft.rest == nil && oldDraft.sets.allSatisfy { $0.rir == nil })
    var oldResult = try JSONSerialization.jsonObject(with: JSONEncoder().encode(run.result())) as! [String: Any]
    oldResult.removeValue(forKey: "run")
    let decodedOld = try JSONDecoder().decode(WorkoutResult.self, from: JSONSerialization.data(withJSONObject: oldResult))
    precondition(decodedOld.run == nil)
    print("PASS: live workout pause/recovery timing, interval guidance, kilometer interpolation, manual laps, stale HR and zone boundaries, GPS accuracy/jumps/gaps, stable result identity, Codable compatibility, RIR validation and persistent rest timing")
  }
}
