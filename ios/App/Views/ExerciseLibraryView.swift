import SwiftUI

struct ExerciseLibraryView: View {
  var onSelect: ((CatalogExercise) -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var equipment = "All equipment"
  @State private var muscle = "All muscles"

  var body: some View {
    Group {
      switch ExerciseCatalog.loaded {
      case .success(let exercises): library(exercises)
      case .failure:
        ContentUnavailableView("Library unavailable", systemImage: "books.vertical",
          description: Text("The bundled exercise library could not be opened. Your gym preferences are still saved."))
      }
    }
    .navigationTitle(onSelect == nil ? "Exercise library" : "Choose exercise")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $search, prompt: "Search exercises")
  }

  private func library(_ exercises: [CatalogExercise]) -> some View {
    let filtered = exercises.filter {
      (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) &&
      (equipment == "All equipment" || $0.equipment == equipment) &&
      (muscle == "All muscles" || $0.primaryMuscles.contains(muscle))
    }
    return List {
      Section {
        Picker("Equipment", selection: $equipment) {
          Text("All equipment").tag("All equipment")
          ForEach(Array(Set(exercises.compactMap(\.equipment))).sorted(), id: \.self) { Text($0.capitalized).tag($0) }
        }
        Picker("Primary muscle", selection: $muscle) {
          Text("All muscles").tag("All muscles")
          ForEach(Array(Set(exercises.flatMap(\.primaryMuscles))).sorted(), id: \.self) { Text($0.capitalized).tag($0) }
        }
      }
      Section("\(filtered.count) exercises") {
        ForEach(filtered) { exercise in
          if let onSelect {
            Button { onSelect(exercise); dismiss() } label: { row(exercise) }.buttonStyle(.plain)
          } else {
            NavigationLink { ExerciseLibraryDetailView(exercise: exercise) } label: { row(exercise) }
          }
        }
        if filtered.isEmpty { ContentUnavailableView.search(text: search) }
      }
      Section {
        Link("Free Exercise DB · Public domain", destination: ExerciseCatalog.sourceURL)
      } footer: {
        Text("An offline reference library. Equipment labels identify the primary category; review each exercise’s setup for additional requirements.")
      }
    }
  }

  private func row(_ exercise: CatalogExercise) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(exercise.name).font(.headline)
      Text(exercise.primaryMuscles.map(\.capitalized).joined(separator: ", ") + " · " + (exercise.equipment?.capitalized ?? "Equipment unspecified"))
        .font(.caption).foregroundStyle(.secondary)
    }.padding(.vertical, 5)
  }
}

private struct ExerciseLibraryDetailView: View {
  var exercise: CatalogExercise
  var body: some View {
    List {
      Section {
        HStack {
          MuscleIllustration(selected: exercise.focusMuscles).frame(height: 180)
          MuscleIllustration(selected: exercise.focusMuscles, posterior: true).frame(height: 180)
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
        Text(exercise.name).font(.title2.weight(.semibold))
        LabeledContent("Primary muscles", value: exercise.primaryMuscles.joined(separator: ", ").capitalized)
        LabeledContent("Equipment", value: exercise.equipment?.capitalized ?? "Unspecified")
        LabeledContent("Level", value: exercise.level.capitalized)
        if !exercise.secondaryMuscles.isEmpty {
          LabeledContent("Secondary muscles", value: exercise.secondaryMuscles.joined(separator: ", ").capitalized)
        }
      }
      Section("How to perform") {
        if exercise.instructions.isEmpty {
          Text("This library entry doesn’t include movement instructions.").foregroundStyle(.secondary)
        }
        ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, instruction in
          HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(SessionPalette.ink(.violet))
              .frame(width: 24, height: 24).background(SessionPalette.wash(.violet), in: Circle())
            Text(instruction).font(.subheadline)
          }.padding(.vertical, 6).accessibilityElement(children: .combine)
        }
      }
      Section { Link("Source: Free Exercise DB", destination: ExerciseCatalog.sourceURL) }
    }
    .navigationTitle("Exercise").navigationBarTitleDisplayMode(.inline)
  }
}
