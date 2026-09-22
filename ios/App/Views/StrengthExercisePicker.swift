import SwiftUI

/// A scoped choice for a PR entry. The exercise catalog stays an internal data source.
struct StrengthExercisePicker: View {
  var onSelect: (CatalogExercise) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""

  private let commonIDs = [
    "Barbell_Bench_Press_-_Medium_Grip", "Barbell_Full_Squat", "Barbell_Deadlift",
    "Standing_Military_Press", "Dumbbell_Bench_Press", "Bent_Over_Barbell_Row", "Pullups"
  ]
  private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    Group {
      switch ExerciseCatalog.loaded {
      case .success(let exercises):
        let choices = query.isEmpty ? commonIDs.compactMap { id in exercises.first { $0.id == id } } :
          exercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
        List {
          Section {
            ForEach(choices) { exercise in
              Button {
                onSelect(exercise)
                dismiss()
              } label: {
                HStack(spacing: 12) {
                  Text(exercise.name).foregroundStyle(HybrdStyle.ink)
                  Spacer(minLength: 8)
                  Image(systemName: "plus").foregroundStyle(SessionPalette.ink(.violet)).accessibilityHidden(true)
                }.padding(.vertical, 7)
              }
            }
            if choices.isEmpty { ContentUnavailableView.search(text: query) }
          } header: { Text(query.isEmpty ? "Common lifts" : "Matching lifts") } footer: {
            Text("Choose the movement for this personal record.")
          }
        }
      case .failure:
        ContentUnavailableView("Movements unavailable", systemImage: "dumbbell",
          description: Text("Movement choices couldn’t be loaded. Your existing records are still saved."))
      }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .navigationTitle("Choose lift").navigationBarTitleDisplayMode(.inline)
    .searchable(text: $search, prompt: "Find a movement")
  }
}
