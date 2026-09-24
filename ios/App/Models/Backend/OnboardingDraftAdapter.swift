import Foundation

/// One-way, explicitly reviewed attachment of a complete anonymous manual draft.
/// Restored connected drafts stay in BackendWire so imported zones/records/fractions are never lost.
enum OnboardingDraftAdapter {
  static func reviewedManualDraft(_ draft: OnboardingDraft, catalog: BackendWire.ExerciseCatalog,
    baseline: BackendWire.OnboardingDraftBaselinePeriod, timeZone: TimeZone, locale: String,
    weekStartsOn: Int, now: Date = Date(), requireComplete: Bool = true) throws -> BackendWire.OnboardingDraft {
    guard (!requireComplete || draft.validation(for: .summary, now: now) == nil), (1...7).contains(weekStartsOn),
          (2...35).contains(locale.count) else { throw BackendContractError.invalidDraft }
    guard baseline.start <= baseline.end else { throw BackendContractError.invalidBaselinePeriod }
    let body = BackendWire.AthleteDetails(preferredName: draft.displayName.isEmpty ? nil : draft.displayName,
      heightUnit: draft.selectedHeightUnit == .centimeters ? .cm : .ftIn,
      age: try draft.ageYears.map { .init(years: $0, asOf: try BackendDay(date: now, timeZone: timeZone)) },
      weightKg: draft.weightKilograms, heightCm: draft.heightCentimeters, runningRecords: [], strengthRecords: [])
    let profile = BackendWire.AthleteProfileInput(timezone: timeZone.identifier, locale: locale,
      distanceUnit: draft.units.distance == .kilometers ? .km : .mi,
      loadUnit: draft.units.weight == .kilograms ? .kg : .lb, weekStartsOn: weekStartsOn, cloudAiConsent: false)
    return BackendWire.OnboardingDraft(schemaVersion: .value1, profile: profile, details: body,
      runningGoal: runningGoal(draft.runningGoal), strengthGoal: strengthGoal(draft.strengthGoal),
      raceDate: try draft.hasRaceDate && draft.runningGoal != .fitness ? BackendDay(date: draft.raceDate, timeZone: timeZone) : nil,
      priority: priority(draft.priority), runningLevel: experience(draft.runningLevel), strengthLevel: experience(draft.strengthLevel),
      weeklyDistanceM: draft.weeklyMeters, currentStrengthSessionsPerWeek: Double(draft.currentLiftDays), baselinePeriod: baseline,
      availableDays: draft.availableDays.sorted(), desiredStrengthSessionsPerWeek: draft.strengthDays,
      sessionMinutes: BackendWire.OnboardingDraftSessionMinutes(rawValue: draft.sessionMinutes),
      equipmentIds: try equipmentIDs(draft.equipment, in: catalog), equipmentConfirmed: draft.equipmentConfirmed,
      focusMuscleIds: try muscleIDs(draft.focusMuscles, in: catalog),
      readiness: draft.readiness.flatMap { BackendWire.OnboardingDraftReadiness(rawValue: $0.rawValue) },
      context: draft.context.isEmpty ? nil : draft.context, wantsHealth: draft.wantsHealth, wantsStrava: draft.wantsStrava,
      membership: draft.membership == .annual ? .annual : .monthly, importDecisions: [])
  }
  static func step(_ native: OnboardingStep) -> BackendWire.OnboardingStateStep {
    switch native {
    case .identity: .identity
    case .goals, .balance: .goals
    case .running, .strength: .baseline
    case .body: .body
    case .rhythm: .schedule
    case .equipment: .equipment
    case .focus: .focus
    case .readiness: .readiness
    case .connections: .connections
    case .summary: .review
    case .paywall: .membership
    }
  }
  static func equipmentIDs(_ values: Set<GymEquipment>, in catalog: BackendWire.ExerciseCatalog) throws -> [UUID] {
    try values.sorted { $0.rawValue < $1.rawValue }.map { item in
      let slug = equipmentSlug(item), matches = catalog.equipment.filter { $0.slug == slug }
      guard matches.count == 1 else { throw BackendContractError.missingCatalogMapping(slug) }
      return matches[0].id
    }
  }
  static func muscleIDs(_ values: Set<MuscleGroup>, in catalog: BackendWire.ExerciseCatalog) throws -> [UUID] {
    try values.sorted { $0.rawValue < $1.rawValue }.map { item in
      let matches = catalog.muscleGroups.filter { $0.slug == item.rawValue }
      guard matches.count == 1 else { throw BackendContractError.missingCatalogMapping(item.rawValue) }
      return matches[0].id
    }
  }
  static func equipmentSlug(_ item: GymEquipment) -> String {
    switch item {
    case .dumbbells: "dumbbells"
    case .barbell: "barbell"
    case .kettlebell: "kettlebell"
    case .ezBar: "ez-curl-bar"
    case .plates: "weight-plates"
    case .bench: "bench"
    case .rack: "rack"
    case .pullUpBar: "pull-up-bar"
    case .cableMachine: "cable-machine"
    case .legPress: "leg-press"
    case .legExtension: "leg-extension"
    case .legCurl: "leg-curl"
    case .chestPress: "chest-press"
    case .latPulldown: "lat-pulldown"
    case .seatedRow: "seated-row"
    case .smithMachine: "smith-machine"
    case .bands: "resistance-band"
    case .medicineBall: "medicine-ball"
    case .stabilityBall: "stability-ball"
    case .foamRoll: "foam-roller"
    }
  }
  private static func runningGoal(_ value: RunningGoal?) -> BackendWire.OnboardingDraftRunningGoal? {
    switch value { case .fitness: .fitness; case .fiveK: .value5k; case .tenK: .value10k; case .halfMarathon: .halfMarathon; case .marathon: .marathon; case nil: nil }
  }
  private static func strengthGoal(_ value: StrengthGoal?) -> BackendWire.OnboardingDraftStrengthGoal? {
    switch value { case .build: .strength; case .muscle: .hypertrophy; case .maintain: .maintenance; case nil: nil }
  }
  private static func priority(_ value: TrainingPriority?) -> BackendWire.OnboardingDraftPriority? {
    switch value { case .balanced: .balanced; case .running: .runFirst; case .strength: .strengthFirst; case nil: nil }
  }
  private static func experience(_ value: TrainingExperience?) -> BackendWire.OnboardingDraftRunningLevel? {
    switch value { case .new: .new; case .beginner: .beginner; case .intermediate: .intermediate; case .advanced: .advanced; case nil: nil }
  }
}
