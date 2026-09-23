import Foundation

enum GymEquipment: String, Codable, CaseIterable, Identifiable {
  case dumbbells, barbell, kettlebell, ezBar, plates
  case bench, rack, pullUpBar, cableMachine
  case legPress, legExtension, legCurl, chestPress, latPulldown, seatedRow, smithMachine
  case bands, medicineBall, stabilityBall, foamRoll
  var id: String { rawValue }
  var title: String {
    switch self {
    case .dumbbells: L10n.text("Dumbbells")
    case .barbell: L10n.text("Barbell")
    case .kettlebell: L10n.text("Kettlebells")
    case .ezBar: L10n.text("EZ curl bar")
    case .plates: L10n.text("Weight plates")
    case .bench: L10n.text("Adjustable bench")
    case .rack: L10n.text("Squat rack")
    case .pullUpBar: L10n.text("Pull-up bar")
    case .cableMachine: L10n.text("Cable station")
    case .legPress: L10n.text("Leg press")
    case .legExtension: L10n.text("Leg extension")
    case .legCurl: L10n.text("Leg curl")
    case .chestPress: L10n.text("Chest press")
    case .latPulldown: L10n.text("Lat pulldown")
    case .seatedRow: L10n.text("Seated row")
    case .smithMachine: L10n.text("Smith machine")
    case .bands: L10n.text("Resistance bands")
    case .medicineBall: L10n.text("Medicine ball")
    case .stabilityBall: L10n.text("Stability ball")
    case .foamRoll: L10n.text("Foam roller")
    }
  }
  var category: String {
    switch self {
    case .dumbbells, .barbell, .kettlebell, .ezBar, .plates: L10n.text("Free weights")
    case .bench, .rack, .pullUpBar, .cableMachine: L10n.text("Benches & stations")
    case .bands, .medicineBall, .stabilityBall, .foamRoll: L10n.text("Accessories")
    default: L10n.text("Machines")
    }
  }
  var symbol: String {
    switch self {
    case .dumbbells, .barbell, .kettlebell, .ezBar, .plates: "dumbbell"
    case .bench: "chair.lounge"
    case .rack, .pullUpBar: "figure.strengthtraining.functional"
    case .medicineBall, .stabilityBall: "circle"
    case .bands: "figure.flexibility"
    case .foamRoll: "cylinder"
    default: "figure.strengthtraining.traditional"
    }
  }
  static var categories: [String] { [L10n.text("Free weights"), L10n.text("Benches & stations"), L10n.text("Machines"), L10n.text("Accessories")] }
}
