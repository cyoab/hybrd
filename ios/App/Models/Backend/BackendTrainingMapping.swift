import Foundation

enum BackendTrainingMapping {
  static func convert<T: Decodable, S: Encodable>(_ source: S, to: T.Type = T.self) throws -> T {
    try JSONDecoder().decode(T.self, from: OnboardingAPIClient.encode(source))
  }
  static func exerciseID(_ name: String, catalog: BackendWire.ExerciseCatalog) throws -> UUID {
    let activeIDs = Set(catalog.exercises.filter(\.active).map(\.id))
    let ids = Set(catalog.exercises.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.active }.map(\.id) +
      catalog.aliases.filter { $0.alias.caseInsensitiveCompare(name) == .orderedSame && activeIDs.contains($0.exerciseId) }.map(\.exerciseId))
    guard ids.count == 1, let id = ids.first else { throw BackendContractError.missingCatalogMapping(name) }; return id
  }
  static func exerciseName(_ id: UUID, catalog: BackendWire.ExerciseCatalog) throws -> String {
    guard let name = catalog.exercises.first(where: { $0.id == id })?.name else { throw BackendContractError.missingCatalogMapping(id.uuidString) }; return name
  }
  static func state(records: [BackendWire.SyncChange], athleteID: UUID, name: String, catalog: BackendWire.ExerciseCatalog, retaining old: TrainingState?) throws -> TrainingState {
    var profile = TrainingProfile(name: name, runningGoal: .fitness, weeklyKilometers: 0, isSample: false, athlete: AthleteDetails())
    profile.backendProfile = true
    var plans: [BackendWire.PlanVersionRecord] = [], results: [WorkoutResult] = []
    var activePlans = Set<UUID>(); var availability: [BackendWire.AvailabilityRuleRecord] = []; var newestBaseline: BackendWire.BaselineRecord?
    var equipmentIDs: [UUID] = []
    for change in records where !change.metadata.deleted {
      switch change {
      case .athlete(let c):
        if let v = c.payload { profile.units = TrainingUnits(weight: v.loadUnit == .lb ? .pounds : .kilograms, distance: v.distanceUnit == .mi ? .miles : .kilometers) }
      case .athleteDetails(let c):
        if let v = c.payload?.details {
          profile.name = v.preferredName ?? name; profile.athlete?.weightKilograms = v.weightKg; profile.athlete?.heightCentimeters = v.heightCm
          profile.athlete?.reportedAge = v.age?.years
          profile.athlete?.birthDate = try v.dateOfBirth.map { try ConnectedDraftMapping.date($0) }
          if let zones = v.heartRateZones, zones.ranges.count == 5 {
            let starts = zones.ranges.dropFirst().map(\.minBpm)
            if starts.allSatisfy({ $0.rounded() == $0 && (30...250).contains($0) }) {
              profile.athlete?.heartRateZones = PersonalHeartRateZones(zone2: Int(starts[0]), zone3: Int(starts[1]), zone4: Int(starts[2]), zone5: Int(starts[3]))
            }
          }
          profile.athlete?.runningBests = v.runningRecords.compactMap { r in
            guard let distance = recordDistances.first(where: { abs($0.value - r.distanceM) < 0.01 })?.key else { return nil }
            return RunningPersonalBest(distance: distance, seconds: r.elapsedSeconds)
          }
          profile.athlete?.strengthBests = try v.strengthRecords.map { r in
            StrengthPersonalBest(exerciseID: r.exerciseId.uuidString, exerciseName: try exerciseName(r.exerciseId, catalog: catalog), kilograms: r.loadKg, reps: r.reps)
          }
        }
      case .trainingPreferences(let c):
        if let v = c.payload {
          profile.priority = v.priorityMode == .runFirst ? .running : v.priorityMode == .strengthFirst ? .strength : .balanced
          profile.strengthGoal = v.strengthObjective == .hypertrophy ? .muscle : v.strengthObjective == .maintenance ? .maintain : .build
          if let b = v.onboarding {
            profile.strengthDays = b.desiredStrengthSessionsPerWeek
            profile.athlete?.runningLevel = ConnectedDraftMapping.level(b.runningLevel); profile.athlete?.strengthLevel = ConnectedDraftMapping.level(b.strengthLevel)
            profile.athlete?.focusMuscles = try ConnectedDraftMapping.muscles(b.focusMuscleIds, catalog: catalog)
            profile.athlete?.gymConfigured = true
          }
        }
      case .athleteGoal(let c):
        if let g = c.payload, g.discipline == .running, g.status == .active {
          switch g.targetValue { case 5000: profile.runningGoal = .fiveK; case 10000: profile.runningGoal = .tenK; case 21097: profile.runningGoal = .halfMarathon; case 42195: profile.runningGoal = .marathon; default: profile.runningGoal = .fitness }
        }
      case .availabilityRule(let c): if let v = c.payload { availability.append(v) }
      case .athleteEquipment(let c): if let v = c.payload, v.available { equipmentIDs.append(v.equipmentId) }
      case .baselineSnapshot(let c): if let v = c.payload, newestBaseline == nil || v.createdAt.date > newestBaseline!.createdAt.date { newestBaseline = v }
      case .planVersion(let c): if let v = c.payload { plans.append(v) }
      case .trainingBlock(let c): if let v = c.payload, v.status == .active, let id = v.activePlanVersionId { activePlans.insert(id) }
      case .workoutResult(let c): if let v = c.payload {
        var restored = try result(v, catalog: catalog)
        // Routes, active time and overlapping native laps have no lossless cloud representation.
        // Keep the local recording alongside the server's canonical summary after every pull.
        if let recorded = old?.results.first(where: { $0.id == restored.id })?.run { restored.run = recorded }
        results.append(restored)
      }
      default: break
      }
    }
    if case .number(let n) = newestBaseline?.metrics["weeklyDistanceM"] { profile.weeklyKilometers = NSDecimalNumber(decimal: n).doubleValue / 1000 }
    if !availability.isEmpty {
      profile.availableDays = Set(availability.filter(\.available).map(\.dayOfWeek))
      profile.sessionMinutes = availability.filter(\.available).compactMap(\.maxSessionMinutes).min() ?? 45
    }
    profile.athlete?.equipment = try ConnectedDraftMapping.equipment(equipmentIDs, catalog: catalog)
    var nativePlans = try plans.sorted { $0.createdAt.date < $1.createdAt.date }.map { p in
      if var cached = old?.plans.first(where: { $0.id == p.id }) { cached.profile = profile; return cached }
      return TrainingPlan(id: p.id, basePlanID: p.basePlanVersionId, createdAt: p.createdAt.date, reason: p.summary ?? "", profile: profile, workouts: try p.workouts.map { try workout($0, catalog: catalog, zones: profile.athlete?.heartRateZones) })
    }
    let active = nativePlans.filter { activePlans.contains($0.id) }.last
    // Draft/rejected candidates never become the visible active plan just because they're newest.
    nativePlans.removeAll { activePlans.contains($0.id) }
    nativePlans.append(active ?? TrainingPlan(id: athleteID, reason: "", profile: profile, workouts: []))
    return TrainingState(profile: profile, plans: nativePlans, results: results, drafts: old?.drafts ?? [])
  }
  static let recordDistances: [RunRecordDistance: Double] = [.mile: 1609.344, .fiveK: 5000, .tenK: 10000, .half: 21097, .marathon: 42195]
  static func workout(_ value: BackendWire.PlannedWorkoutInput, catalog: BackendWire.ExerciseCatalog, zones: PersonalHeartRateZones? = nil) throws -> TrainingWorkout {
    switch value {
    case .running(let v):
      var segments: [RunSegment] = []
      for block in v.run.blocks.sorted(by: { $0.sequence < $1.sequence }) {
        // Expand grouped repeats in their original order: work/recovery/work/recovery.
        for iteration in 0..<block.repeatCount {
          for s in block.steps.sorted(by: { $0.sequence < $1.sequence }) {
            let phase: RunSegmentPhase = s.stepKind == .warmup ? .warmUp : s.stepKind == .cooldown ? .coolDown : s.stepKind == .recovery ? .recovery : s.stepKind == .steady ? .easy : .work
            let target = [s.paceMinSPerKm.map { String(format: "%.0f s/km", $0) }, s.hrMinBpm.map { "\($0)–\(s.hrMaxBpm ?? $0) bpm" }].compactMap { $0 }.joined(separator: " · ")
            let zoneStarts = zones.map { [20] + $0.starts }
            let targetZone = zoneStarts.flatMap { starts in starts.indices.first { index in s.hrMinBpm == starts[index] && s.hrMaxBpm == (index == 4 ? 250 : starts[index + 1] - 1) } }.flatMap { HeartRateZone(rawValue: $0 + 1) }
            segments.append(RunSegment(id: iteration == 0 ? s.id : UUID(), title: block.label ?? s.stepKind.rawValue, seconds: s.durationS ?? 0, cue: s.notes ?? target, phase: phase, target: target.isEmpty ? nil : target, heartRateZone: targetZone))
          }
        }
      }
      return TrainingWorkout(id: v.id, logicalID: v.logicalWorkoutId, date: try ConnectedDraftMapping.date(v.scheduledDate, zone: v.timezone), timeZoneID: v.timezone, kind: .run, title: v.title, purpose: v.purpose ?? "", minutes: (v.estimatedDurationS ?? 0) / 60, distanceMeters: v.plannedDistanceM ?? 0, effort: v.instructions ?? "", isKey: v.priority == .key, segments: segments, isOptional: v.priority == .optional, runType: RunWorkoutType(rawValue: v.workoutType))
    case .strength(let v):
      return TrainingWorkout(id: v.id, logicalID: v.logicalWorkoutId, date: try ConnectedDraftMapping.date(v.scheduledDate, zone: v.timezone), timeZoneID: v.timezone, kind: .strength, title: v.title, purpose: v.purpose ?? "", minutes: (v.estimatedDurationS ?? 0) / 60, isKey: v.priority == .key,
        exercises: try v.strength.exercises.sorted { $0.sequence < $1.sequence }.map { e in
          ExercisePrescription(id: e.id, name: try exerciseName(e.exerciseId, catalog: catalog), note: e.notes ?? "", restSeconds: e.sets.first?.restS ?? 90,
            sets: e.sets.sorted { $0.setNumber < $1.setNumber }.map { SetPrescription(id: $0.id, reps: $0.repsMin ?? 0, targetRIR: Int($0.rirMin ?? 0)) })
        }, isOptional: v.priority == .optional)
    }
  }
  static func result(_ value: BackendWire.WorkoutResultRecord, catalog: BackendWire.ExerciseCatalog) throws -> WorkoutResult {
    switch value {
    case .running(let v):
      return WorkoutResult(id: v.id, plannedWorkoutID: v.plannedWorkoutId ?? v.id, logicalWorkoutID: v.logicalWorkoutId ?? v.id,
        completedAt: try v.endedAt?.date ?? ConnectedDraftMapping.date(v.trainingDate, zone: v.timezone), kind: .run,
        status: v.completionStatus == .skipped ? .skipped : v.completionStatus == .completed ? .completed : .partial,
        durationSeconds: v.run?.durationS ?? v.durationS ?? 0, distanceMeters: v.run?.distanceM, effort: Int(v.sessionRpe ?? 0), notes: v.notes ?? "", sets: [], performedStartedAt: v.startedAt?.date, performedEndedAt: v.endedAt?.date, performedTimeZoneID: v.timezone, canonicalTrainingDate: v.trainingDate.rawValue, canonicalElapsedDuration: true)
    case .strength(let v):
      return WorkoutResult(id: v.id, plannedWorkoutID: v.plannedWorkoutId ?? v.id, logicalWorkoutID: v.logicalWorkoutId ?? v.id,
        completedAt: try v.endedAt?.date ?? ConnectedDraftMapping.date(v.trainingDate, zone: v.timezone), kind: .strength,
        status: v.completionStatus == .skipped ? .skipped : v.completionStatus == .completed ? .completed : .partial,
        durationSeconds: v.durationS ?? 0, effort: Int(v.sessionRpe ?? 0), notes: v.notes ?? "",
        sets: try v.exercises.flatMap { e in try e.sets.map { s in
          LoggedSet(id: s.id, prescriptionID: s.prescribedSetId, exerciseName: try exerciseName(e.exerciseId, catalog: catalog), reps: s.reps ?? 0, kilograms: s.loadKg ?? 0, isComplete: s.status == .completed, rir: s.rir.map(Int.init))
        } }, performedStartedAt: v.startedAt?.date, performedEndedAt: v.endedAt?.date, performedTimeZoneID: v.timezone, canonicalTrainingDate: v.trainingDate.rawValue, canonicalElapsedDuration: true)
    }
  }
  static func resultMutation(_ r: WorkoutResult, state: TrainingState, catalog: BackendWire.ExerciseCatalog, knownPlans: Set<UUID>) throws -> BackendMutation {
    let workout = state.plans.flatMap(\.workouts).first { $0.id == r.plannedWorkoutID }
    let zone = (r.run?.recordedTimeZoneID ?? r.performedTimeZoneID).flatMap { TimeZone(identifier: $0) } ?? .current
    let planned = knownPlans.contains(r.plannedWorkoutID) && workout?.logicalID == r.logicalWorkoutID
    let start = r.run?.startedAt ?? r.performedStartedAt
    let end = r.run?.endedAt ?? r.performedEndedAt
    let day = try BackendDay(date: start ?? r.completedAt, timeZone: zone)
    let logged = try BackendInstant(ISO8601DateFormatter().string(from: r.completedAt))
    let started = try start.map { try BackendInstant(ISO8601DateFormatter().string(from: $0)) }
    let ended = try end.map { try BackendInstant(ISO8601DateFormatter().string(from: $0)) }
    let basis: BackendWire.WorkoutResultInputRunningDateBasis = start == nil ? .loggedDate : .performedDate
    var elapsed: Int?
    if let start, let end {
      let seconds = end.timeIntervalSince(start)
      guard seconds.isFinite, (0...604800).contains(seconds) else { throw BackendContractError.invalidDraft }
      elapsed = Int(seconds.rounded())
    } else if r.kind == .run { elapsed = r.durationSeconds } // Explicitly entered run duration, not invented timing.
    let status: BackendWire.WorkoutResultInputRunningCompletionStatus = r.status == .skipped ? .skipped : r.status == .partial ? .partial : .completed
    if r.kind == .run {
      func bpm(_ value: Double?) -> Int? { value.flatMap { $0.isFinite && (20...250).contains($0) ? Int($0.rounded()) : nil } }
      let payload = BackendWire.WorkoutResultInputRunning(plannedWorkoutId: planned ? r.plannedWorkoutID : nil, logicalWorkoutId: planned ? r.logicalWorkoutID : nil,
        trainingDate: day, timezone: zone.identifier, dateBasis: basis, loggedAt: logged, durationS: elapsed, startedAt: started, endedAt: ended,
        completionStatus: status, sourceType: .manual, sessionRpe: r.effort > 0 ? Double(r.effort) : nil, notes: r.notes, discipline: .running,
        run: r.status == .skipped ? nil : .init(distanceM: r.distanceMeters ?? 0, durationS: elapsed ?? r.durationSeconds, avgHrBpm: bpm(r.run?.averageHeartRate), maxHrBpm: bpm(r.run?.maximumHeartRate)))
      return try BackendMutation(.result, id: r.id, operation: .create, revision: nil, payload: payload)
    }
    let names = r.sets.map(\.exerciseName).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    let exercises = try names.enumerated().map { index, name in
      let e = workout?.exercises.first { $0.name == name }
      return BackendWire.WorkoutResultInputStrengthExercisesItem(id: UUID(), prescribedExerciseId: planned ? e?.id : nil,
        exerciseId: try exerciseID(name, catalog: catalog), sequence: index,
        sets: r.sets.filter { $0.exerciseName == name }.enumerated().map { i, s in
          .init(id: s.id, prescribedSetId: planned ? s.prescriptionID : nil, setNumber: i + 1, setKind: .working, reps: s.reps, loadKg: s.kilograms,
            loadConvention: .external, rir: s.rir.map(Double.init), status: s.isComplete ? .completed : .skipped)
        })
    }
    return try BackendMutation(.result, id: r.id, operation: .create, revision: nil, payload: BackendWire.WorkoutResultInputStrength(
      plannedWorkoutId: planned ? r.plannedWorkoutID : nil, logicalWorkoutId: planned ? r.logicalWorkoutID : nil, trainingDate: day, timezone: zone.identifier,
      dateBasis: basis, loggedAt: logged, durationS: elapsed, startedAt: started, endedAt: ended, completionStatus: status, sourceType: .manual,
      sessionRpe: r.effort > 0 ? Double(r.effort) : nil, notes: r.notes, discipline: .strength, exercises: exercises))
  }
}
