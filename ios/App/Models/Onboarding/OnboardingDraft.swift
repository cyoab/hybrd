import Foundation

/// An isolated research draft, deliberately separate from the live athlete and training plan.
struct OnboardingDraft: Codable, Equatable {
  var name = ""
  var runningGoal: RunningGoal?
  var strengthGoal: StrengthGoal?
  var priority: TrainingPriority?
  var hasRaceDate = false
  var raceDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
  var runningLevel: TrainingExperience?
  var strengthLevel: TrainingExperience?
  var weeklyDistance = ""
  var currentLiftDays = 0
  var age = ""
  var weight = ""
  var height = ""
  var units = TrainingUnits.metric
  var availableDays: Set<Int> = []
  var strengthDays = 2
  var sessionMinutes = 45
  var equipment: Set<GymEquipment> = []
  var equipmentConfirmed = false
  var focusMuscles: Set<MuscleGroup> = []
  var readiness: OnboardingReadiness?
  var context = ""
  var wantsHealth = false
  var wantsStrava = false
  var membership = OnboardingMembership.annual
  // Retain exact physical quantities while toggling display units.
  var distanceBaseline: Double?
  var distanceBaselineText: String?
  var weightBaseline: Double?
  var weightBaselineText: String?

  var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  var weeklyMeters: Double? {
    if weeklyDistance == distanceBaselineText { return distanceBaseline }
    return units.distance.parse(weeklyDistance, meters: 0...250_000)
  }
  var weightKilograms: Double? {
    if weight == weightBaselineText { return weightBaseline }
    return units.weight.parse(weight, kilograms: 20...400)
  }
  var heightCentimeters: Double? { TrainingProfile.parseDecimal(height, range: 80...250) }
  var ageYears: Int? { Int(age.trimmingCharacters(in: .whitespacesAndNewlines)) }

  mutating func setDistanceUnit(_ unit: TrainingDistanceUnit) {
    guard unit != units.distance else { return }
    let meters = weeklyMeters
    units.distance = unit
    if let meters {
      weeklyDistance = units.distanceInput(meters)
      distanceBaseline = meters; distanceBaselineText = weeklyDistance
    } else {
      distanceBaseline = nil; distanceBaselineText = nil
    }
  }
  mutating func setWeightUnit(_ unit: TrainingWeightUnit) {
    guard unit != units.weight else { return }
    let kg = weightKilograms
    units.weight = unit
    if let kg {
      weight = units.weightInput(kg)
      weightBaseline = kg; weightBaselineText = weight
    } else {
      weightBaseline = nil; weightBaselineText = nil
    }
  }
  func validation(for step: OnboardingStep, now: Date = Date()) -> String? {
    switch step {
    case .identity:
      if displayName.isEmpty || displayName.count > 40 { return L10n.text("Enter a name with 1–40 characters.") }
    case .goals:
      if runningGoal == nil || strengthGoal == nil { return L10n.text("Choose a running goal and a strength goal.") }
      if hasRaceDate && runningGoal != .fitness && raceDate < Calendar.current.startOfDay(for: now) { return L10n.text("Choose a race date from today onward.") }
    case .balance:
      if priority == nil { return L10n.text("Choose the balance that feels right for you.") }
    case .running:
      if runningLevel == nil { return L10n.text("Choose your current running experience.") }
      if weeklyMeters == nil { return L10n.text("Enter your recent weekly distance, including zero if you’re starting out.") }
    case .strength:
      if strengthLevel == nil { return L10n.text("Choose your current lifting experience.") }
      if !(0...7).contains(currentLiftDays) { return L10n.text("Choose 0–7 lifting sessions per week.") }
    case .body:
      if !age.isEmpty && !(ageYears.map { (1...120).contains($0) } ?? false) { return L10n.text("Enter a valid age, or leave it blank.") }
      if !weight.isEmpty && weightKilograms == nil { return L10n.text("Check your weight and selected unit, or leave it blank.") }
      if !height.isEmpty && heightCentimeters == nil { return L10n.text("Enter a height from 80 to 250 cm, or leave it blank.") }
    case .rhythm:
      if availableDays.count < 2 || !availableDays.isSubset(of: Set(1...7)) { return L10n.text("Choose at least two training days.") }
      if !(1...4).contains(strengthDays) || strengthDays > availableDays.count { return L10n.text("Choose lifting days within your weekly availability.") }
      if ![30, 45, 60, 75, 90].contains(sessionMinutes) { return L10n.text("Choose a session length.") }
    case .equipment:
      if !equipmentConfirmed { return L10n.text("Choose a setup or select your available equipment.") }
    case .readiness:
      if readiness == nil { return L10n.text("Choose how you’re approaching training right now.") }
      if context.count > 300 { return L10n.text("Keep your note within 300 characters.") }
    case .summary, .paywall:
      return OnboardingStep.allCases.filter { $0.rawValue < OnboardingStep.summary.rawValue }
        .compactMap { validation(for: $0, now: now) }.first
    case .focus, .connections: break
    }
    return nil
  }

  var personalMessage: String {
    if readiness == .returning { return L10n.text("We’ll make room to rebuild your rhythm. Your starting point is enough.") }
    if readiness == .adjusting { return L10n.text("Flexibility belongs in your training. Your plan should fit your life as it changes.") }
    switch priority {
    case .running: return L10n.text("Your running leads the way. Strength supports the athlete behind every run.")
    case .strength: return L10n.text("Your lifting gets the spotlight. Running helps build your engine alongside it.")
    default: return L10n.text("You don’t have to choose one kind of athlete. We’ll make space for both.")
    }
  }
}
