import SwiftUI

struct ProgressHistoryView: View {
  var results: [WorkoutResult]
  var workoutTitles: [UUID: String]
  var day: Date?
  @Environment(\.dismiss) private var dismiss
  @State private var limit = 50

  var body: some View {
    NavigationStack {
      List {
        if results.isEmpty {
          ContentUnavailableView(L10n.text("Space to recover"), systemImage: "leaf", description: Text(L10n.text("No training logged for this day. Rest is part of your rhythm.")))
        }
        ForEach(results.prefix(limit)) { result in
          NavigationLink {
            ProgressResultDetailView(result: result, title: workoutTitles[result.plannedWorkoutID] ?? result.kind.displayName)
          } label: { ProgressHistoryRow(result: result, title: workoutTitles[result.plannedWorkoutID] ?? result.kind.displayName) }
        }
        if results.count > limit { Button(L10n.text("Show more sessions")) { limit += 50 } }
      }
      .scrollContentBackground(.hidden).background(HybrdStyle.background)
      .navigationTitle(day?.formatted(date: .abbreviated, time: .omitted) ?? L10n.text("Training history"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Close"), systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
    }
  }
}

struct ProgressHistoryRow: View {
  @Environment(\.trainingUnits) private var units
  var result: WorkoutResult
  var title: String
  var body: some View {
    HStack(spacing: 13) {
      Image(systemName: result.kind.symbol)
        .foregroundStyle(result.kind == .run ? HybrdStyle.terraText : SessionPalette.ink(.violet))
        .frame(width: 42, height: 42)
        .background(SessionPalette.wash(result.kind == .run ? .terra : .violet), in: RoundedRectangle(cornerRadius: 13))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(L10n.content(title)).font(.subheadline.weight(.semibold))
        Text(result.completedAt.formatted(date: .abbreviated, time: .omitted) + " · " + result.status.displayName)
          .font(.caption).foregroundStyle(HybrdStyle.muted)
        Text(result.kind == .run ? units.distanceText(Double(result.distanceMeters ?? 0)) + L10n.text(" · \(result.durationSeconds / 60) min") :
          L10n.text("\(ProgressSnapshot.validSets(result).count) completed sets"))
          .font(.caption.weight(.medium))
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.vertical, 5).accessibilityElement(children: .combine)
  }
}
