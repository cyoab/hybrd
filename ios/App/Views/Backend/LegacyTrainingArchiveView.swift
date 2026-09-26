import SwiftUI

struct LegacyTrainingArchiveView: View {
  @Environment(TrainingStore.self) private var training
  var body: some View {
    Form {
      Section {
        Text(L10n.text("Training recorded before sign-in stays on this device. You can review or export it here; it is not added to your account."))
      }
      if let error = training.legacyArchiveError {
        Section {
          Text(error)
          Button(L10n.text("Try again")) { training.loadLegacyArchive() }
        }
      }
      ForEach(training.legacyArchives) { archive in
        Section {
          if let state = archive.state {
            Text(state.profile.name).font(.headline)
            let titles = Dictionary(state.plans.flatMap(\.workouts).map { ($0.id, $0.title) }, uniquingKeysWith: { _, newest in newest })
            ForEach(state.results.sorted { $0.completedAt > $1.completedAt }) { result in
              NavigationLink {
                ProgressResultDetailView(result: result, title: titles[result.plannedWorkoutID] ?? result.kind.displayName)
                  .environment(\.trainingUnits, state.profile.trainingUnits)
              } label: {
                ProgressHistoryRow(result: result, title: titles[result.plannedWorkoutID] ?? result.kind.displayName)
                  .environment(\.trainingUnits, state.profile.trainingUnits)
              }
            }
            ForEach(state.drafts) { draft in
              VStack(alignment: .leading, spacing: 4) {
                Text(draft.workout.title).font(.headline)
                Text(L10n.text("In progress")).font(.caption).foregroundStyle(.secondary)
                if !draft.notes.isEmpty { Text(draft.notes).font(.subheadline) }
              }
            }
          }
          ShareLink(L10n.text("Export local training"), item: archive.exportText)
        }
      }
    }
    .navigationTitle(L10n.text("Local training archive"))
    .navigationBarTitleDisplayMode(.inline)
  }
}
