import SwiftUI

struct RunWorkoutPreviewView: View {
  @Environment(TrainingStore.self) private var store
  var template: RunWorkoutTemplate
  var onAdded: (Date) -> Void
  @State private var prescription: TrainingWorkout
  @State private var date: Date
  @State private var reviewedPlan: TrainingPlan
  @State private var saveError: String?

  init(template: RunWorkoutTemplate, selectedDate: Date, plan: TrainingPlan, onAdded: @escaping (Date) -> Void) {
    self.template = template
    self.onAdded = onAdded
    let date = max(Calendar.current.startOfDay(for: selectedDate), Calendar.current.startOfDay(for: Date()))
    _date = State(initialValue: date)
    _prescription = State(initialValue: template.workout(on: date))
    _reviewedPlan = State(initialValue: plan)
  }

  private var workout: TrainingWorkout {
    var result = prescription
    result.date = date
    return result
  }
  private var sameDay: [TrainingWorkout] {
    reviewedPlan.workouts.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
  }
  private var nearbyKeySession: Bool {
    workout.isKey && reviewedPlan.workouts.contains {
      $0.isKey && abs(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
        to: Calendar.current.startOfDay(for: $0.date)).day ?? 99) <= 1
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        SessionHeroView(workout: workout)
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 8) {
            Text(template.subtitle).font(.title3.weight(.semibold))
            Text(template.purpose).font(.subheadline).foregroundStyle(HybrdStyle.muted)
            Text("Time-based session · distance is logged after your run.")
              .font(.caption).foregroundStyle(RunPalette.ink(template.type))
          }
          VStack(alignment: .leading, spacing: 14) {
            DatePicker("Add to your week", selection: $date,
              in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
            if sameDay.isEmpty {
              Text("No other sessions planned for this day.")
                .font(.subheadline).foregroundStyle(HybrdStyle.muted)
            } else {
              Text("Also on this day").font(.subheadline.weight(.semibold))
              ForEach(sameDay) { session in
                Label(session.title + " · \(session.minutes) min", systemImage: session.kind.symbol)
                  .font(.subheadline).foregroundStyle(HybrdStyle.muted)
              }
            }
            if nearbyKeySession {
              Label("Another key session is within a day. Consider leaving more recovery between them.", systemImage: "calendar.badge.exclamationmark")
                .font(.subheadline).foregroundStyle(HybrdStyle.terraText)
            }
            if template.minutes > reviewedPlan.profile.sessionMinutes {
              Text("This is longer than your usual \(reviewedPlan.profile.sessionMinutes)-minute session limit.")
                .font(.caption).foregroundStyle(HybrdStyle.muted)
            }
          }
          .padding(17).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
          RunPrescriptionView(workout: workout)
          Text("Adds one session to your plan. Your other workouts stay as scheduled.")
            .font(.caption).foregroundStyle(HybrdStyle.muted)
        }
        .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
      }
    }
    .background(HybrdStyle.background)
    .navigationTitle("Review workout")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(RunPalette.top(template.type), for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .safeAreaInset(edge: .bottom) {
      Button("Add to plan", systemImage: "plus") {
        if store.addRun(template, on: date, expectedPlanID: reviewedPlan.id) {
          onAdded(date)
        } else {
          saveError = store.errorMessage ?? "The session couldn’t be saved. Please try again."
          store.errorMessage = nil
        }
      }
      .buttonStyle(HybrdPrimaryButtonStyle())
      .padding(.horizontal, 20).padding(.vertical, 12).background(HybrdStyle.surface)
    }
    .alert("Couldn’t add workout", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
      Button("Review latest schedule") { reviewedPlan = store.plan }
      Button("Cancel", role: .cancel) {}
    } message: { Text(saveError ?? "") }
  }
}
