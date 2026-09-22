import Foundation

enum ExerciseCatalog {
  static let sourceURL = URL(string: "https://github.com/yuhonas/free-exercise-db")!
  static let loaded: Result<[CatalogExercise], Error> = Result {
    guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") ??
      Bundle.main.url(forResource: "exercises", withExtension: "json", subdirectory: "Resources/ExerciseCatalog") else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try JSONDecoder().decode([CatalogExercise].self, from: Data(contentsOf: url))
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

struct CatalogExercise: Codable, Identifiable {
  var id: String
  var name: String
  var level: String
  var equipment: String?
  var primaryMuscles: [String]
  var secondaryMuscles: [String]
  var instructions: [String]
  var category: String
  var focusMuscles: Set<MuscleGroup> {
    Set(MuscleGroup.allCases.filter { !$0.catalogMuscles.isDisjoint(with: Set(primaryMuscles)) })
  }
}
