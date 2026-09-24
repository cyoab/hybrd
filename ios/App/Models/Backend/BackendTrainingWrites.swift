import Foundation

@MainActor enum BackendTrainingWrites {
  static func mutations(from old: TrainingState, to next: TrainingState, replica: BackendReplica,
    catalog: BackendWire.ExerciseCatalog, policy: BackendWire.TrainingPolicy) throws -> [BackendMutation] {
    var changes: [BackendMutation] = []
    if old.profile != next.profile { changes += try profile(from: old.profile, to: next.profile, replica: replica, catalog: catalog, policy: policy) }
    if let plan = next.plans.last, plan.id != old.plans.last?.id {
      // Planning uses the last acknowledged setup, so profile changes must be synced first.
      guard old.profile == next.profile else { throw BackendContractError.pendingRequestNeedsReview }
      changes += try planMutations(plan, replica: replica, catalog: catalog, policy: policy)
    }
    let known = Set(replica.records.flatMap { c -> [UUID] in
      guard case .planVersion(let p) = c, let plan = p.payload else { return [] }
      return plan.workouts.map { switch $0 { case .running(let w): w.id; case .strength(let w): w.id } }
    })
    for r in next.results where !old.results.contains(where: { $0.id == r.id }) {
      changes.append(try BackendTrainingMapping.resultMutation(r, state: next, catalog: catalog, knownPlans: known))
    }
    return changes
  }
  private static func profile(from old: TrainingProfile, to p: TrainingProfile, replica: BackendReplica, catalog: BackendWire.ExerciseCatalog, policy: BackendWire.TrainingPolicy) throws -> [BackendMutation] {
    var mutations: [BackendMutation] = []; let id = replica.snapshot.scope.athleteID
    func add<T: Encodable>(_ type: BackendMutation.Entity, _ entityID: UUID = UUID(), _ value: T) throws {
      let revision = replica.revision(type, entityID)
      mutations.append(try BackendMutation(type, id: entityID, operation: revision == nil ? .create : .update, revision: revision, payload: value))
    }
    let detailsRecord = replica.records.compactMap { c -> BackendWire.AthleteDetailsRecord? in if case .athleteDetails(let v) = c { return v.payload }; return nil }.first
    if p.name != old.name || p.athlete != old.athlete {
      var details = detailsRecord?.details ?? .init(heightUnit: .cm, runningRecords: [], strengthRecords: [])
      let d = p.athlete ?? AthleteDetails(), before = old.athlete ?? AthleteDetails()
      details.preferredName = p.name; details.weightKg = d.weightKilograms; details.heightCm = d.heightCentimeters
      if d.birthDate != before.birthDate { details.age = nil; details.dateOfBirth = try d.birthDate.map { try BackendDay(date: $0, timeZone: .current) } }
      if d.heartRateZones != before.heartRateZones {
        details.heartRateZones = d.heartRateZones.map { z in
          let starts = [0] + z.starts
          return .init(schemaVersion: .value1, configuration: .custom, ranges: starts.enumerated().map { i, start in
            .init(minBpm: Double(start), maxBpm: i < 4 ? Double(starts[i + 1]) : nil)
          })
        }
      }
      if d.runningBests != before.runningBests {
        details.runningRecords = d.runningBests.map { .init(distanceM: BackendTrainingMapping.recordDistances[$0.distance]!, elapsedSeconds: $0.seconds, classification: .athleteReported) }
      }
      if d.strengthBests != before.strengthBests {
        details.strengthRecords = try d.strengthBests.map { .init(exerciseId: try BackendTrainingMapping.exerciseID($0.exerciseName, catalog: catalog), loadKg: $0.kilograms, reps: $0.reps, classification: .athleteReported) }
      }
      try add(.athleteDetails, id, BackendWire.AthleteDetailsInput(schemaVersion: .value1, details: details))
    }
    for c in replica.records where !c.metadata.deleted {
      switch c {
      case .athlete(let v): if let source = v.payload, p.trainingUnits != old.trainingUnits {
        var input: BackendWire.AthleteProfileInput = try BackendTrainingMapping.convert(source)
        input.distanceUnit = p.trainingUnits.distance == .miles ? .mi : .km; input.loadUnit = p.trainingUnits.weight == .pounds ? .lb : .kg
        try add(.athlete, id, input)
      }
      case .trainingPreferences(let v): if let source = v.payload {
        var input: BackendWire.TrainingPreferencesInput = try BackendTrainingMapping.convert(source)
        if p.priority != old.priority {
          input.priorityMode = p.priority == .running ? .runFirst : p.priority == .strength ? .strengthFirst : .balanced
          let weights = policy.config.onboarding?.priorityWeights
          input.runPriorityWeight = p.priority == .running ? weights?.runFirst ?? 0.65 : p.priority == .strength ? weights?.strengthFirst ?? 0.35 : weights?.balanced ?? 0.5
          input.strengthPriorityWeight = 1 - input.runPriorityWeight
        }
        if p.strengthGoal != old.strengthGoal { input.strengthObjective = p.strengthGoal == .muscle ? .hypertrophy : p.strengthGoal == .maintain ? .maintenance : .strength }
        if var b = input.onboarding {
          b.desiredStrengthSessionsPerWeek = p.strengthDays
          b.focusMuscleIds = try OnboardingDraftAdapter.muscleIDs(p.athlete?.focusMuscles ?? [], in: catalog)
          if let level = p.athlete?.runningLevel { b.runningLevel = levelWire(level) }
          if let level = p.athlete?.strengthLevel { b.strengthLevel = levelWire(level) }
          input.onboarding = b
        }
        let previous: BackendWire.TrainingPreferencesInput = try BackendTrainingMapping.convert(source)
        if input != previous { try add(.preferences, id, input) }
      }
      case .availabilityRule(let v): if let source = v.payload, p.availableDays != old.availableDays || p.sessionMinutes != old.sessionMinutes {
        var input: BackendWire.AvailabilityRuleInput = try BackendTrainingMapping.convert(source)
        input.available = p.availableDays.contains(source.dayOfWeek); input.maxSessions = input.available ? 1 : 0
        input.maxSessionMinutes = p.sessionMinutes; input.minSessionMinutes = min(input.minSessionMinutes ?? p.sessionMinutes, p.sessionMinutes)
        try add(.availability, source.id, input)
      }
      case .athleteGoal(let v): if let source = v.payload, source.status == .active {
        var input: BackendWire.AthleteGoalInput = try BackendTrainingMapping.convert(source)
        if source.discipline == .strength, p.strengthGoal != old.strengthGoal {
          input.goalType = p.strengthGoal == .muscle ? "hypertrophy" : p.strengthGoal == .maintain ? "maintenance" : "strength"
          try add(.goal, source.id, input)
        }
        if source.discipline == .running, p.runningGoal != old.runningGoal {
          input.goalType = p.runningGoal == .fitness ? "general_fitness" : "race"
          input.targetValue = [RunningGoal.fiveK: 5000.0, .tenK: 10000, .halfMarathon: 21097, .marathon: 42195][p.runningGoal]
          input.targetUnit = input.targetValue == nil ? nil : .meters; input.targetDate = nil
          try add(.goal, source.id, input)
        }
      }
      default: break
      }
    }
    if p.athlete?.equipment != old.athlete?.equipment {
      let selected = Set(try OnboardingDraftAdapter.equipmentIDs(p.athlete?.equipment ?? [], in: catalog))
      let existing = replica.records.compactMap { c -> BackendWire.AthleteEquipmentRecord? in if case .athleteEquipment(let v) = c, !c.metadata.deleted { return v.payload }; return nil }
      for e in existing where e.available != selected.contains(e.equipmentId) { try add(.equipment, e.id, BackendWire.AthleteEquipmentInput(equipmentId: e.equipmentId, available: selected.contains(e.equipmentId))) }
      for id in selected where !existing.contains(where: { $0.equipmentId == id }) { try add(.equipment, UUID(), BackendWire.AthleteEquipmentInput(equipmentId: id, available: true)) }
    }
    if p.weeklyKilometers != old.weeklyKilometers {
      let now = Date(), start = Calendar.current.date(byAdding: .day, value: -28, to: now)!
      try add(.baseline, UUID(), BackendWire.BaselineInput(periodStart: try BackendDay(date: start, timeZone: .current), periodEnd: try BackendDay(date: now, timeZone: .current), schemaVersion: .value1,
        metrics: ["weeklyDistanceM": .number(Decimal(p.weeklyKilometers * 1000)), "onboardingMetricsVersion": .number(1)], confidence: [:], source: .manual))
    }
    return mutations
  }
  static func levelWire(_ value: TrainingExperience) -> BackendWire.OnboardingDraftRunningLevel {
    switch value { case .new: .new; case .beginner: .beginner; case .intermediate: .intermediate; case .advanced: .advanced }
  }
  private static func planMutations(_ plan: TrainingPlan, replica: BackendReplica, catalog: BackendWire.ExerciseCatalog, policy: BackendWire.TrainingPolicy) throws -> [BackendMutation] {
    let contexts = replica.records.compactMap { c -> BackendWire.PlanningContextRecord? in if case .planningContextSnapshot(let v) = c { return v.payload }; return nil }
    guard let context = contexts.max(by: { $0.createdAt.date < $1.createdAt.date }) else { throw BackendContractError.restoreRequired }
    var snapshot: BackendWire.PlanningContextInputSnapshot = try BackendTrainingMapping.convert(context.snapshot)
    var baselineID = context.baselineSnapshotId
    let records = replica.records.filter { !$0.metadata.deleted }
    snapshot.goals = try records.compactMap { c -> BackendWire.AthleteGoalInput? in if case .athleteGoal(let v) = c, let p = v.payload { return try BackendTrainingMapping.convert(p) }; return nil }
    snapshot.availabilityRules = try records.compactMap { c -> BackendWire.AvailabilityRuleInput? in if case .availabilityRule(let v) = c, let p = v.payload { return try BackendTrainingMapping.convert(p) }; return nil }
    snapshot.equipmentIds = records.compactMap { c in if case .athleteEquipment(let v) = c, let p = v.payload, p.available { return p.equipmentId }; return nil }
    for c in records {
      if case .trainingPreferences(let v) = c, let p = v.payload { snapshot.preferences = try BackendTrainingMapping.convert(p) }
      if case .athleteDetails(let v) = c, let p = v.payload { snapshot.athleteDetailsId = p.id; snapshot.athleteDetailsSnapshot = .init(revision: p.revision, details: p.details) }
    }
    let latestBaseline = records.compactMap { c -> BackendWire.BaselineRecord? in if case .baselineSnapshot(let v) = c { return v.payload }; return nil }.max { $0.createdAt.date < $1.createdAt.date }
    if let latestBaseline { baselineID = latestBaseline.id; snapshot.recentFeatures = latestBaseline.metrics }
    let newContextID = UUID()
    var output = [try BackendMutation(.context, id: newContextID, operation: .create, revision: nil,
      payload: BackendWire.PlanningContextInput(baselineSnapshotId: baselineID, schemaVersion: .value1, policyVersionId: policy.id, snapshot: snapshot))]
    let previous = records.compactMap { c -> BackendWire.PlanVersionRecord? in if case .planVersion(let v) = c, v.payload?.id == plan.basePlanID { return v.payload }; return nil }.first
    let blockID = previous?.trainingBlockId ?? UUID()
    guard let first = plan.workouts.map(\.date).min(), let last = plan.workouts.map(\.date).max() else { throw BackendContractError.invalidDraft }
    if previous == nil { output.append(try BackendMutation(.block, id: blockID, operation: .create, revision: nil,
      payload: BackendWire.TrainingBlockInput(name: "hybrd", startDate: try BackendDay(date: first, timeZone: .current), endDate: try BackendDay(date: last, timeZone: .current), phase: .build, status: .active))) }
    if let previous, let block = records.compactMap({ c -> BackendWire.TrainingBlockRecord? in if case .trainingBlock(let v) = c, v.payload?.id == previous.trainingBlockId { return v.payload }; return nil }).first {
      let start = try BackendDay(date: first, timeZone: .current), end = try BackendDay(date: last, timeZone: .current)
      if start < block.startDate || end > block.endDate {
        var expanded: BackendWire.TrainingBlockInput = try BackendTrainingMapping.convert(block)
        expanded.startDate = min(start, block.startDate); expanded.endDate = max(end, block.endDate)
        output.append(try BackendMutation(.block, id: block.id, operation: .update, revision: block.revision, payload: expanded))
      }
    }
    let workouts = try plan.workouts.map { workout in
      if let preserved = previous?.workouts.first(where: { switch $0 { case .running(let v): v.logicalWorkoutId == workout.logicalID; case .strength(let v): v.logicalWorkoutId == workout.logicalID } }) {
        return try movedPrescription(preserved, to: workout)
      }
      return try prescription(workout, catalog: catalog, zones: plan.profile.athlete?.heartRateZones)
    }
    output.append(try BackendMutation(.plan, id: plan.id, operation: .create, revision: nil,
      payload: BackendWire.PlanVersionInput(trainingBlockId: blockID, basePlanVersionId: previous?.id, planningContextSnapshotId: newContextID, policyVersionId: policy.id, origin: previous == nil ? .initial : .manualEdit, summary: plan.reason, workouts: workouts)))
    output.append(try BackendMutation(.plan, id: plan.id, operation: .activatePlan, revision: nil,
      payload: BackendWire.ActivatePlanInput(expectedActivePlanVersionId: previous?.id, accepted: BackendTrue(), reasonCode: "athlete_accepted", explanation: plan.reason)))
    return output
  }
  /// Preserve server prescriptions exactly when rescheduling; native display models aren't a lossless wire editor.
  private static func movedPrescription(_ source: BackendWire.PlannedWorkoutInput, to w: TrainingWorkout) throws -> BackendWire.PlannedWorkoutInput {
    let day = try BackendDay(date: w.date, timeZone: TimeZone(identifier: w.timeZoneID) ?? .current)
    func movedStart(_ start: BackendInstant?, from original: BackendDay, zone: String) throws -> BackendInstant? {
      guard original != day, let start else { return start }
      var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone) ?? .current
      let clock = calendar.dateComponents([.hour, .minute, .second], from: start.date)
      guard let date = calendar.date(bySettingHour: clock.hour!, minute: clock.minute!, second: clock.second!, of: try ConnectedDraftMapping.date(day, zone: zone)) else { throw BackendContractError.invalidDate }
      return try BackendInstant(ISO8601DateFormatter().string(from: date))
    }
    switch source {
    case .running(var v):
      v.scheduledStartAt = try movedStart(v.scheduledStartAt, from: v.scheduledDate, zone: v.timezone)
      v.scheduledDate = day; v.id = v.id == w.id ? UUID() : w.id
      for b in v.run.blocks.indices { v.run.blocks[b].id = UUID(); for i in v.run.blocks[b].steps.indices { v.run.blocks[b].steps[i].id = UUID() } }
      return .running(v)
    case .strength(var v):
      v.scheduledStartAt = try movedStart(v.scheduledStartAt, from: v.scheduledDate, zone: v.timezone)
      v.scheduledDate = day; v.id = v.id == w.id ? UUID() : w.id
      guard v.strength.exercises.count == w.exercises.count else { throw BackendContractError.invalidDraft }
      for e in v.strength.exercises.indices {
        v.strength.exercises[e].id = v.strength.exercises[e].id == w.exercises[e].id ? UUID() : w.exercises[e].id
        guard v.strength.exercises[e].sets.count == w.exercises[e].sets.count else { throw BackendContractError.invalidDraft }
        for i in v.strength.exercises[e].sets.indices {
          let id = w.exercises[e].sets[i].id
          v.strength.exercises[e].sets[i].id = v.strength.exercises[e].sets[i].id == id ? UUID() : id
        }
      }
      return .strength(v)
    }
  }
  private static func prescription(_ w: TrainingWorkout, catalog: BackendWire.ExerciseCatalog, zones: PersonalHeartRateZones?) throws -> BackendWire.PlannedWorkoutInput {
    let date = try BackendDay(date: w.date, timeZone: TimeZone(identifier: w.timeZoneID) ?? .current)
    let priority: BackendWire.PlannedWorkoutInputRunningPriority = w.isOptional == true ? .optional : w.isKey ? .key : .supporting
    if w.kind == .run {
      let blocks = RunTimeline(segments: w.segments).steps.enumerated().map { index, step in
        let s = step.segment
        let zone = s.heartRateZone?.rawValue
        let starts = zones.map { [20] + $0.starts }
        let lower = zone.flatMap { z in starts.map { $0[z - 1] } }
        let upper = zone.flatMap { z in starts.map { z == 5 ? 250 : $0[z] - 1 } }
        return BackendWire.PlannedWorkoutInputRunningRunBlocksItem(id: UUID(), sequence: index, repeatCount: 1, label: s.title,
          steps: [.init(id: UUID(), sequence: 0, stepKind: s.phase == .warmUp ? .warmup : s.phase == .coolDown ? .cooldown : s.phase == .recovery ? .recovery : s.phase == .easy ? .steady : .work,
            durationS: s.seconds, hrMinBpm: lower, hrMaxBpm: upper, notes: s.cue + (s.heartRateZone.map { " · " + $0.shortTitle } ?? ""))])
      }
      return .running(.init(id: w.id, logicalWorkoutId: w.logicalID, workoutType: w.resolvedRunType.rawValue, scheduledDate: date, timezone: w.timeZoneID, title: w.title,
        purpose: w.purpose, priority: priority, estimatedDurationS: w.minutes * 60, plannedDistanceM: w.distanceMeters, instructions: w.effort, discipline: .running,
        run: .init(primaryTargetType: zones == nil ? .open : .heartRate, blocks: blocks)))
    }
    let exercises = try w.exercises.enumerated().map { i, e in
      BackendWire.PlannedWorkoutInputStrengthStrengthExercisesItem(id: e.id, exerciseId: try BackendTrainingMapping.exerciseID(e.name, catalog: catalog), sequence: i,
        substitutionAllowed: true, notes: e.note, sets: e.sets.enumerated().map { j, s in .init(id: s.id, setNumber: j + 1, setKind: .working,
          repsMin: s.reps, repsMax: s.reps, rirMin: Double(s.targetRIR), rirMax: Double(s.targetRIR), restS: e.restSeconds) })
    }
    return .strength(.init(id: w.id, logicalWorkoutId: w.logicalID, workoutType: "strength", scheduledDate: date, timezone: w.timeZoneID, title: w.title, purpose: w.purpose,
      priority: priority, estimatedDurationS: w.minutes * 60, discipline: .strength, strength: .init(sessionFocus: w.title, exercises: exercises)))
  }
}
