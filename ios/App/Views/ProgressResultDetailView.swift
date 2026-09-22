import SwiftUI

struct ProgressResultDetailView: View {
  @Environment(\.trainingUnits) private var units
  var result: WorkoutResult
  var title: String
  var body: some View {
    List {
      Section {
        LabeledContent("Status", value: result.status.rawValue)
        LabeledContent("Logged", value: result.completedAt.formatted(date: .abbreviated, time: .shortened))
        LabeledContent("Active time", value: RunningPersonalBest.format(max(0, result.durationSeconds)))
        if result.kind == .run, let meters = result.distanceMeters {
          LabeledContent("Distance", value: units.distanceText(Double(meters), decimals: 2))
        }
      }
      if result.kind == .strength {
        Section("Completed sets") {
          ForEach(ProgressSnapshot.validSets(result)) { set in
            LabeledContent(set.exerciseName, value: units.weightText(set.kilograms) + " × \(set.reps)" + (set.rir.map { " · \($0) RIR" } ?? ""))
          }
        }
      }
      if let run = result.run { Section { NavigationLink("Route, heart rate & splits") { ScrollView { RunSummaryView(run: run).padding(20) }.background(HybrdStyle.background) } } }
      if !result.notes.isEmpty { Section("Your notes") { Text(result.notes) } }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
  }
}
