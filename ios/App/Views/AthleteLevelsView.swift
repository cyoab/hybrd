import SwiftUI

struct AthleteLevelsView: View {
  @Bindable var editor: AthleteProfileEditor
  var body: some View {
    Form {
      Section {
        Picker("Running", selection: $editor.details.runningLevel) {
          Text("Not set").tag(Optional<TrainingExperience>.none)
          ForEach(TrainingExperience.allCases) { Text($0.rawValue).tag(Optional($0)) }
        }
        if let level = editor.details.runningLevel { Text(level.detail).foregroundStyle(.secondary) }
      } header: { Label("Running level", systemImage: "figure.run") }
      Section {
        Picker("Strength", selection: $editor.details.strengthLevel) {
          Text("Not set").tag(Optional<TrainingExperience>.none)
          ForEach(TrainingExperience.allCases) { Text($0.rawValue).tag(Optional($0)) }
        }
        if let level = editor.details.strengthLevel { Text(level.detail).foregroundStyle(.secondary) }
      } header: { Label("Strength level", systemImage: "dumbbell") } footer: {
        Text("Choose each discipline independently. These describe your experience, not a fitness score.")
      }
    }
    .navigationTitle("Experience").navigationBarTitleDisplayMode(.inline)
  }
}
