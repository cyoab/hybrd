import Foundation

enum ConnectedDraftMapping {
  static func date(_ day: BackendDay, zone: String = TimeZone.current.identifier) throws -> Date {
    let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: zone); f.dateFormat = "yyyy-MM-dd"
    guard let value = f.date(from: day.rawValue) else { throw BackendContractError.invalidDate }; return value
  }
  static func native(_ remote: BackendWire.OnboardingDraft, catalog: BackendWire.ExerciseCatalog) throws -> OnboardingDraft {
    var d = OnboardingDraft()
    d.name = remote.details.preferredName ?? ""
    d.runningGoal = runGoal(remote.runningGoal)
    d.strengthGoal = remote.strengthGoal.map { $0 == .hypertrophy ? .muscle : $0 == .maintenance ? .maintain : .build }
    d.priority = remote.priority.map { $0 == .runFirst ? .running : $0 == .strengthFirst ? .strength : .balanced }
    d.runningLevel = level(remote.runningLevel); d.strengthLevel = level(remote.strengthLevel)
    if let p = remote.profile { d.units = TrainingUnits(weight: p.loadUnit == .lb ? .pounds : .kilograms, distance: p.distanceUnit == .mi ? .miles : .kilometers) }
    if let m = remote.weeklyDistanceM { d.weeklyDistance = d.units.distanceInput(m); d.distanceBaseline = m; d.distanceBaselineText = d.weeklyDistance }
    if let kg = remote.details.weightKg { d.weight = d.units.weightInput(kg); d.weightBaseline = kg; d.weightBaselineText = d.weight }
    if let cm = remote.details.heightCm { d.height = cm.formatted(.number.grouping(.never)); if remote.details.heightUnit == .ftIn { d.setHeightUnit(.feetAndInches) } }
    if let age = remote.details.age { d.age = String(age.years) }
    d.currentLiftDays = remote.currentStrengthSessionsPerWeek ?? 0
    d.availableDays = Set(remote.availableDays ?? []); d.strengthDays = remote.desiredStrengthSessionsPerWeek ?? 2; d.sessionMinutes = remote.sessionMinutes?.rawValue ?? 45
    d.equipment = try equipment(remote.equipmentIds ?? [], catalog: catalog)
    d.equipmentConfirmed = remote.equipmentConfirmed
    d.focusMuscles = try muscles(remote.focusMuscleIds ?? [], catalog: catalog)
    d.readiness = remote.readiness.flatMap { OnboardingReadiness(rawValue: $0.rawValue) }; d.context = remote.context ?? ""
    if let race = remote.raceDate { d.raceDate = try date(race, zone: remote.profile?.timezone ?? TimeZone.current.identifier); d.hasRaceDate = true }
    d.membership = remote.membership == .monthly ? .monthly : .annual
    return d
  }
  /// Update only fields changed in the native editor. Extra imported records, zones, DOB, source decisions and fractions survive.
  static func wire(_ d: OnboardingDraft, original: BackendWire.OnboardingDraft?, catalog: BackendWire.ExerciseCatalog) throws -> BackendWire.OnboardingDraft {
    let zone = original?.profile.flatMap { TimeZone(identifier: $0.timezone) } ?? .current
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let end = calendar.startOfDay(for: Date()), start = calendar.date(byAdding: .day, value: -28, to: end)!
    var w = try OnboardingDraftAdapter.reviewedManualDraft(d, catalog: catalog,
      baseline: original?.baselinePeriod ?? .init(start: try BackendDay(date: start, timeZone: zone), end: try BackendDay(date: end, timeZone: zone)),
      timeZone: zone, locale: original?.profile?.locale ?? Locale.current.identifier, weekStartsOn: original?.profile?.weekStartsOn ?? 2, requireComplete: false)
    w.wantsHealth = false; w.wantsStrava = false; w.membership = nil
    guard let original else { return w }
    let before = try native(original, catalog: catalog)
    var details = original.details
    if d.name != before.name { details.preferredName = w.details.preferredName }
    if d.weightKilograms != before.weightKilograms { details.weightKg = w.details.weightKg }
    if d.heightCentimeters != before.heightCentimeters { details.heightCm = w.details.heightCm }
    if d.age != before.age { details.dateOfBirth = nil; details.age = w.details.age }
    details.heightUnit = w.details.heightUnit; w.details = details
    w.importDecisions = original.importDecisions
    // This test flow doesn't edit provider-derived fields; require a fresh review if provider provenance is present.
    guard original.importDecisions.isEmpty else { throw BackendContractError.pendingRequestNeedsReview }
    return w
  }
  static func step(_ step: BackendWire.OnboardingStateStep?) -> OnboardingStep {
    switch step {
    case .identity, .connections, nil: .identity
    case .goals: .goals
    case .baseline: .running
    case .body: .body
    case .schedule: .rhythm
    case .equipment: .equipment
    case .focus: .focus
    case .readiness: .readiness
    case .review, .preparing, .membership: .summary
    }
  }
  static func level(_ value: BackendWire.OnboardingDraftRunningLevel?) -> TrainingExperience? {
    switch value { case .new: .new; case .beginner: .beginner; case .intermediate: .intermediate; case .advanced: .advanced; case nil: nil }
  }
  static func runGoal(_ value: BackendWire.OnboardingDraftRunningGoal?) -> RunningGoal? {
    switch value { case .fitness: .fitness; case .value5k: .fiveK; case .value10k: .tenK; case .halfMarathon: .halfMarathon; case .marathon: .marathon; case nil: nil }
  }
  static func equipment(_ ids: [UUID], catalog: BackendWire.ExerciseCatalog) throws -> Set<GymEquipment> {
    try Set(ids.map { id in
      guard let slug = catalog.equipment.first(where: { $0.id == id })?.slug,
            let native = GymEquipment.allCases.first(where: { OnboardingDraftAdapter.equipmentSlug($0) == slug }) else { throw BackendContractError.missingCatalogMapping(id.uuidString) }; return native
    })
  }
  static func muscles(_ ids: [UUID], catalog: BackendWire.ExerciseCatalog) throws -> Set<MuscleGroup> {
    try Set(ids.map { id in
      guard let slug = catalog.muscleGroups.first(where: { $0.id == id })?.slug, let native = MuscleGroup(rawValue: slug) else { throw BackendContractError.missingCatalogMapping(id.uuidString) }; return native
    })
  }
}
