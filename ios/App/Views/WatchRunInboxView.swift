import SwiftUI

struct WatchRunInboxView: View {
  @Environment(\.trainingUnits) private var units
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        ForEach(store.companion.receivedRuns) { run in
          Section(run.workout.localizedTitle) {
            Text(units.distanceText(run.meters, decimals: 2) + " · " + RunRecording.clock(run.elapsed))
            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            Text(L10n.text("This planned session already has a result. Keep this recording separately only if it was a different run.")).font(.subheadline)
            Button(L10n.text("Keep as a separate run")) {
              if store.saveRecordedRun(run, asSeparate: true) { store.companion.acknowledge(run) }
            }
            Button(L10n.text("Already recorded · dismiss duplicate")) { store.companion.acknowledge(run) }
          }
        }
      }.navigationTitle(L10n.text("Watch recordings"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
    }
  }
}
