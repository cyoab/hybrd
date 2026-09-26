import SwiftUI

struct ProgressResultDetailView: View {
  @Environment(\.trainingUnits) private var units
  var result: WorkoutResult
  var title: String
  var body: some View {
    List {
      Section {
        LabeledContent(L10n.text("Status"), value: result.status.displayName)
        LabeledContent(L10n.text("Logged"), value: result.completedAt.formatted(date: .abbreviated, time: .shortened))
        LabeledContent(result.canonicalElapsedDuration == true ? L10n.text("Elapsed time") : L10n.text("Active time"), value: RunningPersonalBest.format(max(0, result.durationSeconds)))
        if result.kind == .run, let meters = result.distanceMeters {
          LabeledContent(L10n.text("Distance"), value: units.distanceText(Double(meters), decimals: 2))
        }
      }
      if result.kind == .strength {
        Section(L10n.text("Completed sets")) {
          ForEach(ProgressSnapshot.validSets(result)) { set in
            LabeledContent(set.localizedExerciseName, value: units.weightText(set.kilograms) + " × \(set.reps)" + (set.rir.map { L10n.text(" · \($0) RIR") } ?? ""))
          }
        }
      }
      if let run = result.run { Section { NavigationLink(L10n.text("Route, heart rate & splits")) { ScrollView { RunSummaryView(run: run).padding(20) }.background(HybrdStyle.background) } } }
      if !result.notes.isEmpty { Section(L10n.text("Your notes")) { Text(result.notes) } }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .navigationTitle(L10n.content(title)).navigationBarTitleDisplayMode(.inline)
  }
}
