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
      case .firstDay: "First footprint"
      case .bothDisciplines: "Two lanes"
      case .tenKilometers: "Into your stride"
      case .twentyFiveSets: "Solid foundation"
      case .tenDays: "Finding rhythm"
      case .fiftyKilometers: "Going the distance"
      case .hundredSets: "Built, set by set"
      case .fiftyDays: "The long game"
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
      case .firstDay: "Log your first training day."
      case .bothDisciplines: "Log a run and a strength session, on any days."
      case .tenKilometers: "Reach 10 km of logged running."
      case .twentyFiveSets: "Complete 25 strength sets."
      case .tenDays: "Train on 10 different days."
      case .fiftyKilometers: "Reach 50 km of logged running."
      case .hundredSets: "Complete 100 strength sets."
      case .fiftyDays: "Train on 50 different days."
      }
    }
    func requirement(in units: TrainingUnits) -> String {
      if self == .tenKilometers || self == .fiftyKilometers {
        return "Reach " + units.distanceText(Double(target), decimals: 2) + " of logged running."
      }
      return requirement
    }
    func progressLabel(_ value: Int, units: TrainingUnits = .metric) -> String {
      switch self {
      case .tenKilometers, .fiftyKilometers:
        units.distanceNumber(Double(value), decimals: 2) + " / " + units.distanceText(Double(target), decimals: 2)
      case .twentyFiveSets, .hundredSets: "\(value) / \(target) sets"
      case .bothDisciplines: "\(value) / 2 disciplines"
      default: "\(value) / \(target) training days"
      }
    }
  }
}
