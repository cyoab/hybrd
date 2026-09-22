import Foundation

/// Small reviewed starter recipe library. Public catalog data remains reference-only.
enum StrengthStarterSelection {
  static func moves(lower: Bool, details: AthleteDetails) -> [StarterMovement] {
    let equipment = details.gymConfigured ? details.equipment : Set(GymEquipment.allCases)
    let baseline: [MuscleGroup] = lower ? [.quadriceps, .hamstrings, .glutes, .calves] :
      [.chest, .back, .shoulders, .core, .biceps, .triceps]
    let prioritized = baseline.filter { details.focusMuscles.contains($0) } +
      baseline.filter { !details.focusMuscles.contains($0) }
    return prioritized.prefix(4).compactMap { muscle in
      options.first { $0.muscle == muscle && $0.requires.isSubset(of: equipment) }
    }
  }

  static let options: [StarterMovement] = [
    .init("Goblet squat", .quadriceps, [.dumbbells]),
    .init("Leg press", .quadriceps, [.legPress]),
    .init("Bodyweight squat", .quadriceps, []),
    .init("Romanian deadlift", .hamstrings, [.barbell]),
    .init("Dumbbell Romanian deadlift", .hamstrings, [.dumbbells]),
    .init("Leg curl", .hamstrings, [.legCurl]),
    .init("Hamstring walkout", .hamstrings, []),
    .init("Hip thrust", .glutes, [.barbell, .bench]),
    .init("Dumbbell glute bridge", .glutes, [.dumbbells]),
    .init("Glute bridge", .glutes, []),
    .init("Dumbbell calf raise", .calves, [.dumbbells]),
    .init("Standing calf raise", .calves, []),
    .init("Dumbbell bench press", .chest, [.dumbbells, .bench]),
    .init("Chest press", .chest, [.chestPress]),
    .init("Dumbbell floor press", .chest, [.dumbbells]),
    .init("Push-up", .chest, []),
    .init("Bent-over dumbbell row", .back, [.dumbbells]),
    .init("Seated cable row", .back, [.cableMachine]),
    .init("Seated row", .back, [.seatedRow]),
    .init("Lat pulldown", .back, [.latPulldown]),
    .init("Pull-up", .back, [.pullUpBar]),
    .init("Resistance band row", .back, [.bands]),
    .init("Prone W raise", .back, []),
    .init("Dumbbell shoulder press", .shoulders, [.dumbbells]),
    .init("Overhead press", .shoulders, [.barbell]),
    .init("Pike push-up", .shoulders, []),
    .init("Dead bug", .core, []),
    .init("Dumbbell curl", .biceps, [.dumbbells]),
    .init("Barbell curl", .biceps, [.barbell]),
    .init("Resistance band curl", .biceps, [.bands]),
    .init("Self-resisted biceps curl", .biceps, []),
    .init("Triceps pushdown", .triceps, [.cableMachine]),
    .init("Dumbbell triceps extension", .triceps, [.dumbbells]),
    .init("Close-grip push-up", .triceps, [])
  ]
}

struct StarterMovement {
  var name: String
  var muscle: MuscleGroup
  var requires: Set<GymEquipment>
  init(_ name: String, _ muscle: MuscleGroup, _ requires: Set<GymEquipment>) {
    self.name = name; self.muscle = muscle; self.requires = requires
  }
}
