import Foundation

struct ProgressMilestone: Identifiable {
  var kind: Kind
  var value: Int
  var earnedAt: Date?
  var id: Kind { kind }
  var earned: Bool { earnedAt != nil }
  var fraction: Double { min(1, Double(value) / Double(kind.target)) }

  enum Kind: String, CaseIterable, Identifiable {
    case firstDay, bothDisciplines, tenKilometers, twentyFiveSets, tenDays, fiftyKilometers, hundredSets, fiftyDays
    var id: String { rawValue }
    var title: String {
      switch self {
      case .firstDay: L10n.text("First footprint")
      case .bothDisciplines: L10n.text("Two lanes")
      case .tenKilometers: L10n.text("Into your stride")
      case .twentyFiveSets: L10n.text("Solid foundation")
      case .tenDays: L10n.text("Finding rhythm")
      case .fiftyKilometers: L10n.text("Going the distance")
      case .hundredSets: L10n.text("Built, set by set")
      case .fiftyDays: L10n.text("The long game")
      }
    }
    var symbol: String {
      switch self {
      case .firstDay: "shoeprints.fill"
      case .bothDisciplines: "arrow.triangle.branch"
      case .tenKilometers: "figure.run"
      case .twentyFiveSets: "dumbbell.fill"
      case .tenDays: "sun.max.fill"
      case .fiftyKilometers: "road.lanes"
      case .hundredSets: "trophy.fill"
      case .fiftyDays: "crown.fill"
      }
    }
    var target: Int {
      switch self {
      case .firstDay: 1
      case .bothDisciplines: 2
      case .tenKilometers: 10_000
      case .twentyFiveSets: 25
      case .tenDays: 10
      case .fiftyKilometers: 50_000
      case .hundredSets: 100
      case .fiftyDays: 50
      }
    }
    var requirement: String {
      switch self {
      case .firstDay: L10n.text("Log your first training day.")
      case .bothDisciplines: L10n.text("Log a run and a strength session, on any days.")
      case .tenKilometers: L10n.text("Reach 10 km of logged running.")
      case .twentyFiveSets: L10n.text("Complete 25 strength sets.")
      case .tenDays: L10n.text("Train on 10 different days.")
      case .fiftyKilometers: L10n.text("Reach 50 km of logged running.")
      case .hundredSets: L10n.text("Complete 100 strength sets.")
      case .fiftyDays: L10n.text("Train on 50 different days.")
      }
    }
    func requirement(in units: TrainingUnits) -> String {
      if self == .tenKilometers || self == .fiftyKilometers {
        return L10n.text("Reach \(units.distanceText(Double(target), decimals: 2)) of logged running.")
      }
      return requirement
    }
    func progressLabel(_ value: Int, units: TrainingUnits = .metric) -> String {
      switch self {
      case .tenKilometers, .fiftyKilometers:
        units.distanceNumber(Double(value), decimals: 2) + " / " + units.distanceText(Double(target), decimals: 2)
      case .twentyFiveSets, .hundredSets: L10n.text("\(value) / \(target) sets")
      case .bothDisciplines: L10n.text("\(value) / 2 disciplines")
      default: L10n.text("\(value) / \(target) training days")
      }
    }
  }
}
