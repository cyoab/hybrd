import Foundation

struct AthleteDetails: Codable, Equatable {
  var birthDate: Date?
  var weightKilograms: Double?
  var heightCentimeters: Double?
  var runningLevel: TrainingExperience?
  var strengthLevel: TrainingExperience?
  var heartRateZones: PersonalHeartRateZones?
  var runningBests: [RunningPersonalBest] = []
  var strengthBests: [StrengthPersonalBest] = []
  var focusMuscles: Set<MuscleGroup> = []
  var equipment: Set<GymEquipment> = []
  var gymConfigured = false
  var lastHealthImport: Date?

  func age(on date: Date = Date(), calendar: Calendar = .current) -> Int? {
    birthDate.flatMap { calendar.dateComponents([.year], from: $0, to: date).year }
  }
  var validationMessage: String? {
    if let birthDate, birthDate > Date() || (age() ?? 0) > 120 { return L10n.text("Choose a birth date within the last 120 years.") }
    if let weightKilograms, !weightKilograms.isFinite || !(20...400).contains(weightKilograms) { return L10n.text("Enter a weight from 20 to 400 kg, or leave it blank.") }
    if let heightCentimeters, !heightCentimeters.isFinite || !(80...250).contains(heightCentimeters) { return L10n.text("Enter a height from 80 to 250 cm, or leave it blank.") }
    if let heartRateZones, !heartRateZones.isValid { return L10n.text("Heart-rate boundaries must increase from Zone 2 to Zone 5.") }
    if runningBests.contains(where: { !(1...172_800).contains($0.seconds) }) { return L10n.text("Enter valid personal-best times.") }
    if strengthBests.contains(where: { !$0.isValid }) { return L10n.text("Check the weight and reps for your strength records.") }
    return nil
  }
}

enum TrainingExperience: String, Codable, CaseIterable, Identifiable {
  var displayName: String { L10n.content(rawValue) }
  case new = "Just starting", beginner = "Beginner", intermediate = "Intermediate", advanced = "Advanced"
  var id: String { rawValue }
  var detail: String {
    switch self {
    case .new: L10n.text("Building a routine")
    case .beginner: L10n.text("Learning the fundamentals")
    case .intermediate: L10n.text("Training consistently")
    case .advanced: L10n.text("Several years of structured training")
    }
  }
}
