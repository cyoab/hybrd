import Foundation

enum TrainingUnitsChecks {
  static func run() throws {
    let imperial = TrainingUnits(weight: .pounds, distance: .miles)
    let mixed = TrainingUnits(weight: .pounds, distance: .kilometers)
    func near(_ a: Double, _ b: Double, tolerance: Double = 1e-8) { precondition(abs(a - b) < tolerance, "\(a) != \(b)") }
    near(imperial.weight.kilograms(from: 100), 45.359237)
    near(imperial.weight.value(fromKilograms: 45.359237), 100)
    near(imperial.distance.meters(from: 1), 1_609.344)
    near(imperial.distance.value(fromMeters: 5_000), 3.1068559612)
    near(imperial.distance.pace(fromSecondsPerKilometer: 300), 482.8032)
    precondition(imperial.paceNumber(300) == "8:03" && imperial.paceText(nil) == "— /mi")
    precondition(imperial.paceNumber(3_000) == "1:20:28" && imperial.paceNumber(.infinity) == "—")
    precondition(mixed.paceNumber(300) == "5:00" && mixed.weight == .pounds)
    let english = Locale(identifier: "en_US"), german = Locale(identifier: "de_DE")
    near(imperial.weight.parse("135.5", kilograms: 0...1_000, locale: english)!, 61.461766135)
    near(imperial.weight.parse("135,5", kilograms: 0...1_000, locale: german)!, 61.461766135)
    near(imperial.distance.parse("10", meters: 3_000...150_000, locale: english)!, 16_093.44)
    for text in ["NaN", "infinity", "-5", "20lbs", "", "1.2.3"] {
      precondition(imperial.weight.parse(text, kilograms: 0...1_000, locale: english) == nil)
      precondition(imperial.distance.parse(text, meters: 3_000...150_000, locale: english) == nil)
    }
    precondition(imperial.weight.parse("2300", kilograms: 0...1_000, locale: english) == nil)
    precondition(imperial.distance.parse("100", meters: 3_000...150_000, locale: english) == nil)
    var profile = TrainingProfile()
    profile.weeklyKilometers = 70.123456789
    profile.athlete = AthleteDetails()
    profile.athlete?.weightKilograms = 76.123456789
    let editor = AthleteProfileEditor(profile: profile)
    precondition(!editor.hasChanges)
    for _ in 0..<100 {
      editor.setWeightUnit(.pounds); editor.setDistanceUnit(.miles)
      near(editor.assembledProfile.weeklyKilometers, profile.weeklyKilometers)
      near(editor.assembledProfile.athlete!.weightKilograms!, profile.athlete!.weightKilograms!)
      editor.setWeightUnit(.kilograms); editor.setDistanceUnit(.kilometers)
    }
    precondition(!editor.hasChanges, "Toggling and canceling units must not round or dirty old values")
    editor.setWeightUnit(.pounds); editor.setDistanceUnit(.miles)
    editor.weight = "200"; editor.weeklyDistance = "50"
    near(editor.assembledProfile.athlete!.weightKilograms!, 90.718474)
    near(editor.assembledProfile.weeklyKilometers, 80.4672)
    editor.setWeightUnit(.kilograms); editor.setDistanceUnit(.kilometers)
    near(editor.parsedWeightKilograms!, 90.718474)
    near(editor.parsedWeeklyKilometers!, 80.4672)
    editor.weeklyDistance = "invalid"; editor.setDistanceUnit(.miles)
    precondition(editor.units.distance == .kilometers && editor.weeklyDistance == "invalid")
    editor.weight = "invalid"; editor.setWeightUnit(.pounds)
    precondition(editor.units.weight == .kilograms && editor.weight == "invalid")
    editor.importWeight(kilograms: 76.123456789)
    near(editor.parsedWeightKilograms!, 76.123456789)
    var imperialProfile = profile; imperialProfile.units = imperial
    let reopened = AthleteProfileEditor(profile: imperialProfile)
    precondition(!reopened.hasChanges)
    near(reopened.assembledProfile.athlete!.weightKilograms!, profile.athlete!.weightKilograms!)
    let savedProfile = try JSONDecoder().decode(TrainingProfile.self, from: JSONEncoder().encode(imperialProfile))
    precondition(savedProfile == imperialProfile)
    var legacyProfile = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
    legacyProfile.removeValue(forKey: "units")
    let legacy = try JSONDecoder().decode(TrainingProfile.self, from: JSONSerialization.data(withJSONObject: legacyProfile))
    precondition(legacy.trainingUnits == .metric)
    let now = Date(timeIntervalSince1970: 1_000_000)
    let workout = RunWorkoutTemplate.easyThirty.workout(on: now)
    let snapshot = CompanionSnapshot(name: "Athlete", isSample: true, workouts: [workout], units: imperial)
    let savedSnapshot = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONEncoder().encode(snapshot))
    precondition(savedSnapshot.units == imperial)
    var oldSnapshot = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
    oldSnapshot.removeValue(forKey: "units")
    let legacySnapshot = try JSONDecoder().decode(CompanionSnapshot.self, from: JSONSerialization.data(withJSONObject: oldSnapshot))
    precondition(legacySnapshot.units == nil)
    var run = RunRecording(workout: workout, source: .watch, splitUnit: .miles, startedAt: now, runningSince: now, checkpointAt: now)
    run.updateDistance(1_000, at: 300)
    precondition(run.laps.isEmpty, "A mile run must not cue at one kilometer")
    run.updateDistance(3_218.688, at: 965.6064)
    precondition(run.laps.count == 2 && run.laps.allSatisfy { $0.kind == .mile })
    near(run.laps[0].meters, 1_609.344); near(run.laps[0].seconds, 482.8032)
    run.finish(at: now.addingTimeInterval(966))
    precondition(run.result().distanceMeters == 3_219, "Result remains canonical meters")
    let restored = try JSONDecoder().decode(RunRecording.self, from: JSONEncoder().encode(run))
    precondition(restored.splitUnit == .miles && restored.laps == run.laps)
    var oldRun = try JSONSerialization.jsonObject(with: JSONEncoder().encode(RunRecording(workout: workout, source: .watch, startedAt: now, runningSince: now, checkpointAt: now))) as! [String: Any]
    oldRun.removeValue(forKey: "splitUnit")
    var oldRecording = try JSONDecoder().decode(RunRecording.self, from: JSONSerialization.data(withJSONObject: oldRun))
    oldRecording.updateDistance(1_000, at: 300)
    precondition(oldRecording.laps.first?.kind == .kilometer)
    let actual = run.result()
    let baseline = try JSONEncoder().encode(actual)
    _ = imperial.distanceText(Double(actual.distanceMeters!)); _ = mixed.distanceText(Double(actual.distanceMeters!))
    let unchangedResult = try JSONDecoder().decode(WorkoutResult.self, from: baseline)
    precondition(unchangedResult == actual)
    let comparison = ProgressComparison(kind: .run, title: "5 km", subtitle: "Same distance", points: [
      .init(resultID: UUID(), date: now, value: 300),
      .init(resultID: UUID(), date: now.addingTimeInterval(86_400), value: 280)
    ], runDistanceMeters: 5_000, runType: .easy)
    near(comparison.displayValue(300, in: imperial), 482.8032)
    precondition(comparison.changeLabel(in: imperial) == "32 sec/mi faster")
    precondition(comparison.displayTitle(in: imperial).hasPrefix(imperial.distanceText(5_000, decimals: 3)))
    precondition(ProgressMilestone.Kind.tenKilometers.target == 10_000)
    precondition(ProgressMilestone.Kind.tenKilometers.requirement(in: imperial).contains(imperial.distanceText(10_000, decimals: 2)))
    var manual = WorkoutDraft(workout: workout)
    manual.distanceKilometers = imperial.distance.meters(from: 5) / 1_000
    manual.durationMinutes = 45
    precondition(manual.canFinish && Int((manual.distanceKilometers * 1_000).rounded()) == 8_047)
    let kilograms = imperial.weight.kilograms(from: 135)
    var strengthDraft = WorkoutDraft(workout: TrainingEngine.makePlan(profile: TrainingProfile(), start: now).workouts.first { $0.kind == .strength }!)
    strengthDraft.sets[0].kilograms = kilograms; strengthDraft.sets[0].isComplete = true
    precondition(strengthDraft.canFinish)
    near(imperial.weight.value(fromKilograms: strengthDraft.sets[0].kilograms), 135)
    print("PASS: mixed units, exact kg/lb and km/mi conversions, pace, locale-aware entry, range rejection, precision-preserving profile edits/toggles, legacy profiles/Watch snapshots/recordings, canonical results and mile splits")
  }
}
