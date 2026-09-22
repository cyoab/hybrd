import SwiftUI

struct StarterReviewView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var proposal: TrainingPlan
  var onAccepted: () -> Void
  @State private var saveError: String?

  private var firstWeek: [TrainingWorkout] {
    let start = Calendar.current.startOfDay(for: proposal.createdAt)
    let end = TrainingEngine.date(start, offset: 7)
    return proposal.workouts.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Your next chapter")
            Text("Make space for both.").font(.system(.title2, design: .rounded, weight: .semibold))
            Text("Four weeks of easy running and foundational strength. Here’s how your first week fits together.")
              .font(.subheadline).foregroundStyle(HybrdStyle.muted)
          }.padding(.vertical, 10)
          LabeledContent("Running goal", value: proposal.profile.runningGoal.rawValue)
          LabeledContent("Strength goal", value: proposal.profile.strengthGoal.rawValue)
          LabeledContent("Weekly baseline", value: proposal.profile.weeklyKilometers.formatted() + " km")
        }
        Section("First seven days") {
          ForEach(firstWeek) { workout in
            VStack(alignment: .leading, spacing: 6) {
              Text(workout.date.formatted(.dateTime.weekday(.wide))).font(.caption).foregroundStyle(.secondary)
              SessionRow(workout: workout, status: store.status(of: workout))
            }.padding(.vertical, 4)
          }
        }
        Section {
          Text("Running volume stays steady for three weeks, then eases in week four. Session time limits may reduce your requested distance. This is a starter block, not a race-specific plan.")
          Text("Accepting replaces unstarted future sessions. Completed and in-progress sessions and previous plan versions are preserved.")
        }.font(.subheadline).foregroundStyle(HybrdStyle.muted)
      }
      .scrollContentBackground(.hidden).background(HybrdStyle.background)
      .navigationTitle("Review your plan")
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) {
        Button("Accept starter block") {
          if store.accept(proposal: proposal) {
            onAccepted()
          } else {
            saveError = store.errorMessage ?? "Your changes couldn’t be saved. Please try again."
            store.errorMessage = nil
          }
        }
        .buttonStyle(HybrdPrimaryButtonStyle())
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(HybrdStyle.surface)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Back", systemImage: "chevron.left") { dismiss() }.labelStyle(.iconOnly)
        }
      }
      .alert("Couldn’t save changes", isPresented: Binding(
        get: { saveError != nil }, set: { if !$0 { saveError = nil } }
      )) {
        Button("OK") { saveError = nil }
      } message: { Text(saveError ?? "") }
    }
  }
}
