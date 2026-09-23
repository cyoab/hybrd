import SwiftUI

struct MoveSessionView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var workout: TrainingWorkout
  var expectedPlanID: UUID
  @State private var newDate = Date()

  private var conflicts: [String] {
    TrainingEngine.conflicts(for: workout, on: newDate, in: store.plan)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.text("Review the change")) {
          LabeledContent(L10n.text("Session"), value: workout.localizedTitle)
          LabeledContent(L10n.text("From"), value: workout.date.formatted(date: .abbreviated, time: .omitted))
          DatePicker(L10n.text("Move to"), selection: $newDate, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
        }
        if !conflicts.isEmpty {
          Section(L10n.text("Consider your recovery")) {
            ForEach(conflicts, id: \.self) { concern in
              Label(concern, systemImage: "exclamationmark.triangle")
                .font(.subheadline).foregroundStyle(.orange)
            }
          }
        }
        Section {
          Text(L10n.text("Only this session’s date changes. Your previous plan and completed training stay in your history."))
            .font(.subheadline).foregroundStyle(.secondary)
          Button(L10n.text("Accept change")) {
            if store.move(workout, to: newDate, expectedPlanID: expectedPlanID) { dismiss() }
          }.disabled(Calendar.current.isDate(newDate, inSameDayAs: workout.date))
        }
      }
      .navigationTitle(L10n.text("Move session"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
      }
      .onAppear { newDate = max(workout.date, Calendar.current.startOfDay(for: Date())) }
    }
  }
}
