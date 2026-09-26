import Foundation

enum AthleteProfileChecks {
  static func run() throws {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    var legacy = try JSONSerialization.jsonObject(with: encoder.encode(TrainingProfile())) as! [String: Any]
    legacy.removeValue(forKey: "athlete")
    let old = try decoder.decode(TrainingProfile.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(old.athlete == nil && old.weeklyKilometers == 24,
      "Existing athlete profiles and plan snapshots must decode without new fields")

    var profile = old
    var info = AthleteDetails()
    info.weightKilograms = 72.5
    info.heightCentimeters = 178
    info.runningLevel = .intermediate
    info.strengthLevel = .beginner
    info.heartRateZones = PersonalHeartRateZones(zone2: 120, zone3: 140, zone4: 160, zone5: 180)
    info.focusMuscles = [.back, .glutes]
    info.equipment = [.dumbbells, .bench]
    info.gymConfigured = true
    info.runningBests = [RunningPersonalBest(distance: .fiveK, seconds: 1_470)]
    info.strengthBests = [StrengthPersonalBest(exerciseID: "test", exerciseName: "Bench press", kilograms: 80, reps: 5)]
    profile.athlete = info
    precondition(profile.validationMessage == nil)
    let restoredProfile = try decoder.decode(TrainingProfile.self, from: encoder.encode(profile))
    precondition(restoredProfile == profile)
    let snapshot = TrainingEngine.makePlan(profile: profile)
    let restoredSnapshot = try decoder.decode(TrainingPlan.self, from: encoder.encode(snapshot))
    precondition(restoredSnapshot.profile == profile)

    let zones = info.heartRateZones!
    precondition(zones.label(for: .one) == "Below 120 bpm" && zones.label(for: .two) == "120–139 bpm")
    precondition(zones.label(for: .five) == "180+ bpm")
    precondition(!PersonalHeartRateZones(zone2: 120, zone3: 120, zone4: 160, zone5: 180).isValid)
    precondition(!PersonalHeartRateZones(zone2: 140, zone3: 130, zone4: 160, zone5: 180).isValid)
    precondition(!PersonalHeartRateZones(zone2: 29, zone3: 130, zone4: 160, zone5: 180).isValid)

    precondition(RunningPersonalBest.parse("24:30") == 1_470)
    precondition(RunningPersonalBest.parse("1:48:20") == 6_500)
    precondition(RunningPersonalBest.format(6_500) == "1:48:20")
    for invalid in ["", "24", "24:60", "1:99:00", "0:00", "-1:30", "1.5:00", "999999999999999:00"] {
      precondition(RunningPersonalBest.parse(invalid) == nil)
    }

    let editor = AthleteProfileEditor(profile: profile)
    precondition(!editor.hasChanges && editor.validationMessage == nil)
    editor.weight = "72kg"
    precondition(editor.validationMessage != nil && editor.weight == "72kg",
      "Invalid input stays editable and must block saving")
    editor.weight = ""
    editor.height = ""
    precondition(editor.validationMessage == nil)
    precondition(editor.assembledProfile.athlete?.weightKilograms == nil && editor.assembledProfile.athlete?.heightCentimeters == nil,
      "Clearing optional measurements must persist as unknown, never zero")
    editor.zoneStarts = ["120", "", "160", "180"]
    precondition(editor.validationMessage != nil)
    editor.zoneStarts = ["", "", "", ""]
    precondition(editor.validationMessage == nil && editor.assembledProfile.athlete?.heartRateZones == nil)
    editor.runningTimes[.fiveK] = "20:99"
    precondition(editor.validationMessage != nil)
    editor.runningTimes[.fiveK] = ""
    precondition(editor.validationMessage == nil && editor.assembledProfile.athlete?.runningBests.isEmpty == true)

    var invalid = profile
    invalid.athlete?.weightKilograms = .infinity
    precondition(invalid.validationMessage != nil)
    invalid = profile
    invalid.athlete?.birthDate = Date().addingTimeInterval(86_400)
    precondition(invalid.validationMessage != nil)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    info.birthDate = calendar.date(from: DateComponents(year: 2000, month: 10, day: 10))
    precondition(info.age(on: calendar.date(from: DateComponents(year: 2026, month: 10, day: 9))!, calendar: calendar) == 25)
    precondition(info.age(on: calendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!, calendar: calendar) == 26)

    var bodyweight = AthleteDetails()
    bodyweight.gymConfigured = true
    for equipment: Set<GymEquipment> in [[], [.dumbbells], [.barbell, .bench], Set(GymEquipment.allCases)] {
      bodyweight.equipment = equipment
      for lower in [false, true] {
        let moves = StrengthStarterSelection.moves(lower: lower, details: bodyweight)
        precondition(moves.count == 4)
        precondition(moves.allSatisfy { $0.requires.isSubset(of: equipment) },
          "New starter prescriptions must use only selected equipment")
      }
    }
    bodyweight.equipment = []
    bodyweight.focusMuscles = [.biceps]
    precondition(StrengthStarterSelection.moves(lower: false, details: bodyweight).first?.muscle == .biceps)
    var bodyweightProfile = old
    bodyweightProfile.athlete = bodyweight
    let bodyweightPlan = TrainingEngine.makePlan(profile: bodyweightProfile)
    let allowed = Set(StrengthStarterSelection.options.filter { $0.requires.isEmpty }.map(\.name))
    precondition(bodyweightPlan.workouts.flatMap(\.exercises).allSatisfy { allowed.contains($0.name) })
    precondition(snapshot.profile == profile, "Generating a new block must not alter existing snapshots")

    let done = LoggedSet(exerciseName: "Squat", reps: 5, kilograms: 100, isComplete: true)
    let unfinished = LoggedSet(exerciseName: "Squat", reps: 1, kilograms: 200, isComplete: false)
    let moreReps = LoggedSet(exerciseName: "Squat", reps: 6, kilograms: 100, isComplete: true)
    let result = WorkoutResult(plannedWorkoutID: UUID(), logicalWorkoutID: UUID(), kind: .strength,
      status: .partial, durationSeconds: 60, effort: 5, notes: "", sets: [done, unfinished, moreReps])
    let records = LoggedStrengthRecords.candidates(from: [result])
    precondition(records.count == 1 && records[0].kilograms == 100 && records[0].reps == 6 && records[0].source == .logged,
      "Only checked actual sets can become PR candidates; ties prefer more reps")
    var skipped = result
    skipped.status = .skipped
    precondition(LoggedStrengthRecords.candidates(from: [skipped]).isEmpty)

    let catalogURL = URL(fileURLWithPath: "App/Resources/ExerciseCatalog/exercises.json")
    let catalog = try decoder.decode([CatalogExercise].self, from: Data(contentsOf: catalogURL))
    precondition(catalog.count == 876 && Set(catalog.map(\.id)).count == catalog.count)
    precondition(catalog.allSatisfy { !$0.name.isEmpty })
    precondition(catalog.filter { $0.instructions.isEmpty }.count == 5, "The pinned source contains five entries without instructions; the UI must show an explicit empty state")
    precondition(catalog.contains { $0.equipment == "dumbbell" && $0.primaryMuscles.contains("biceps") })
    print("PASS: profile migration/round trips, optional input, HR boundaries, PR validation, logged bests, equipment-safe starter recipes, focus ordering, and pinned public exercise catalog")
  }
}
