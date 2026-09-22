import Foundation

enum GymEquipment: String, Codable, CaseIterable, Identifiable {
  case dumbbells, barbell, kettlebell, ezBar, plates
  case bench, rack, pullUpBar, cableMachine
  case legPress, legExtension, legCurl, chestPress, latPulldown, seatedRow, smithMachine
  case bands, medicineBall, stabilityBall, foamRoll
  var id: String { rawValue }
  var title: String {
    switch self {
    case .dumbbells: "Dumbbells"
    case .barbell: "Barbell"
    case .kettlebell: "Kettlebells"
    case .ezBar: "EZ curl bar"
    case .plates: "Weight plates"
    case .bench: "Adjustable bench"
    case .rack: "Squat rack"
    case .pullUpBar: "Pull-up bar"
    case .cableMachine: "Cable station"
    case .legPress: "Leg press"
    case .legExtension: "Leg extension"
    case .legCurl: "Leg curl"
    case .chestPress: "Chest press"
    case .latPulldown: "Lat pulldown"
    case .seatedRow: "Seated row"
    case .smithMachine: "Smith machine"
    case .bands: "Resistance bands"
    case .medicineBall: "Medicine ball"
    case .stabilityBall: "Stability ball"
    case .foamRoll: "Foam roller"
    }
  }
  var category: String {
    switch self {
    case .dumbbells, .barbell, .kettlebell, .ezBar, .plates: "Free weights"
    case .bench, .rack, .pullUpBar, .cableMachine: "Benches & stations"
    case .bands, .medicineBall, .stabilityBall, .foamRoll: "Accessories"
    default: "Machines"
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
  static var categories: [String] { ["Free weights", "Benches & stations", "Machines", "Accessories"] }
}
