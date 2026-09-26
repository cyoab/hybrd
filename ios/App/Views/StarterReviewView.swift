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
            Eyebrow(text: L10n.text("Your next chapter"))
            Text(L10n.text("Make space for both.")).font(.system(.title2, design: .rounded, weight: .semibold))
            Text(L10n.text("Four weeks of easy running and foundational strength. Here’s how your first week fits together."))
              .font(.subheadline).foregroundStyle(HybrdStyle.muted)
          }.padding(.vertical, 10)
          LabeledContent(L10n.text("Running goal"), value: proposal.profile.runningGoal.displayName)
          LabeledContent(L10n.text("Strength goal"), value: proposal.profile.strengthGoal.displayName)
          if let info = proposal.profile.athlete {
            if info.gymConfigured {
              LabeledContent(L10n.text("Gym setup"), value: info.equipment.isEmpty ? L10n.text("Bodyweight") : L10n.text("\(info.equipment.count) equipment types"))
            }
            if !info.focusMuscles.isEmpty {
              LabeledContent(L10n.text("Muscle focus"), value: MuscleGroup.allCases.filter { info.focusMuscles.contains($0) }.map(\.title).joined(separator: ", "))
            }
          }
          LabeledContent(L10n.text("Weekly baseline"), value: proposal.profile.trainingUnits.distanceText(proposal.profile.weeklyKilometers * 1_000))
        }
        Section(L10n.text("First seven days")) {
          ForEach(firstWeek) { workout in
            VStack(alignment: .leading, spacing: 6) {
              Text(workout.date.formatted(.dateTime.weekday(.wide))).font(.caption).foregroundStyle(.secondary)
              SessionRow(workout: workout, status: store.status(of: workout))
            }.padding(.vertical, 4)
          }
        }
        Section {
          Text(L10n.text("Running volume stays steady for three weeks, then eases in week four. Session time limits may reduce your requested distance. This is a starter block, not a race-specific plan."))
          Text(L10n.text("Accepting replaces unstarted future sessions. Completed and in-progress sessions and previous plan versions are preserved."))
        }.font(.subheadline).foregroundStyle(HybrdStyle.muted)
      }
      .scrollContentBackground(.hidden).background(HybrdStyle.background)
      .navigationTitle(L10n.text("Review your plan"))
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) {
        Button(L10n.text("Accept starter block")) {
          if store.accept(proposal: proposal) {
            onAccepted()
          } else {
            saveError = store.errorMessage ?? L10n.text("Your changes couldn’t be saved. Please try again.")
            store.errorMessage = nil
          }
        }
        .buttonStyle(HybrdPrimaryButtonStyle())
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(HybrdStyle.surface)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Back"), systemImage: "chevron.left") { dismiss() }.labelStyle(.iconOnly)
        }
      }
      .alert(L10n.text("Couldn’t save changes"), isPresented: Binding(
        get: { saveError != nil }, set: { if !$0 { saveError = nil } }
      )) {
        Button(L10n.text("OK")) { saveError = nil }
      } message: { Text(saveError ?? "") }
    }
  }
}
