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
          ContentUnavailableView("Space to recover", systemImage: "leaf", description: Text("No training logged for this day. Rest is part of your rhythm."))
        }
        ForEach(results.prefix(limit)) { result in
          NavigationLink {
            ProgressResultDetailView(result: result, title: workoutTitles[result.plannedWorkoutID] ?? result.kind.rawValue)
          } label: { ProgressHistoryRow(result: result, title: workoutTitles[result.plannedWorkoutID] ?? result.kind.rawValue) }
        }
        if results.count > limit { Button("Show more sessions") { limit += 50 } }
      }
      .scrollContentBackground(.hidden).background(HybrdStyle.background)
      .navigationTitle(day?.formatted(date: .abbreviated, time: .omitted) ?? "Training history")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
    }
  }
}

struct ProgressHistoryRow: View {
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
        Text(title).font(.subheadline.weight(.semibold))
        Text(result.completedAt.formatted(date: .abbreviated, time: .omitted) + " · " + result.status.rawValue)
          .font(.caption).foregroundStyle(HybrdStyle.muted)
        Text(result.kind == .run ? "\(Double(result.distanceMeters ?? 0) / 1_000, specifier: "%.1f") km · \(result.durationSeconds / 60) min" :
          "\(ProgressSnapshot.validSets(result).count) completed sets")
          .font(.caption.weight(.medium))
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.vertical, 5).accessibilityElement(children: .combine)
  }
}
