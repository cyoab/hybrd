import SwiftUI

struct WorkoutDetailView: View {
  @Environment(\.trainingUnits) private var units
  @Environment(TrainingStore.self) private var store
  var workout: TrainingWorkout
  @State private var logging = false
  @State private var moving = false
  @State private var confirmSkip = false

  private var current: TrainingWorkout {
    store.workouts.first { $0.logicalID == workout.logicalID } ?? workout
  }
  private var result: WorkoutResult? { store.result(for: current) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        SessionHeroView(workout: current)
        VStack(alignment: .leading, spacing: 26) {
          if let result { resultCard(result) }

          HStack(alignment: .top, spacing: 14) {
            Image(systemName: "scope").font(.title3).foregroundStyle(HybrdStyle.terraText)
              .padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
              Text(L10n.text("Why this session")).font(.subheadline.weight(.semibold))
              Text(current.purpose).font(.subheadline).foregroundStyle(HybrdStyle.muted)
            }
          }
          Divider().overlay(HybrdStyle.line)
          if current.kind == .run {
            RunPrescriptionView(workout: current)
          } else {
            StrengthPrescriptionView(exercises: current.exercises)
          }
        }
        .padding(20).padding(.bottom, 12)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
      }
    }
    .background(HybrdStyle.background)
    .toolbar(.visible, for: .navigationBar)
    .toolbarBackground(current.kind == .run ? RunPalette.top(current.resolvedRunType) : SessionPalette.liftTop, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .navigationTitle(current.kind == .run ? L10n.text("Run session") : L10n.text("Strength session"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if result == nil && !store.hasDraft(for: current) {
        ToolbarItem(placement: .primaryAction) {
          Menu(L10n.text("Session options"), systemImage: "ellipsis") {
            Button(L10n.text("Move session"), systemImage: "calendar.badge.clock") { moving = true }
            Button(L10n.text("Skip session"), systemImage: "forward.end", role: .destructive) { confirmSkip = true }
          }.labelStyle(.iconOnly)
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if result == nil {
        Button { logging = true } label: {
          Label(store.hasDraft(for: current) ? L10n.text("Continue session") : (current.kind == .strength ? L10n.text("Start workout") : L10n.text("Start run")),
            systemImage: "play.fill")
        }
        .buttonStyle(HybrdPrimaryButtonStyle())
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(HybrdStyle.surface)
        .overlay(alignment: .top) { Rectangle().fill(HybrdStyle.line).frame(height: 0.5) }
      }
    }
    .fullScreenCover(isPresented: $logging) {
      if current.kind == .run { RunSessionView(workout: current) }
      else { WorkoutLoggerView(draft: store.draft(for: current)) }
    }
    .sheet(isPresented: $moving) { MoveSessionView(workout: current, expectedPlanID: store.plan.id) }
    .confirmationDialog(L10n.text("Skip this session?"), isPresented: $confirmSkip, titleVisibility: .visible) {
      Button(L10n.text("Skip session"), role: .destructive) { store.skip(current) }
    } message: {
      Text(L10n.text("It will stay in your history as skipped. We won’t stack it onto another day."))
    }
  }

  private func resultCard(_ result: WorkoutResult) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(result.status.displayName, systemImage: result.status == .skipped ? "forward.end" : "checkmark")
        .font(.headline).foregroundStyle(HybrdStyle.terraText)
      if result.status != .skipped {
        LabeledContent(L10n.text("Actual duration"), value: L10n.text("\(result.durationSeconds / 60) min"))
        if let meters = result.distanceMeters {
          LabeledContent(L10n.text("Actual distance"), value: units.distanceText(Double(meters), decimals: 2))
        } else {
          LabeledContent(L10n.text("Sets completed"), value: "\(result.sets.count)")
          DisclosureGroup(L10n.text("Recorded sets")) {
            ForEach(result.sets) { set in
              LabeledContent(set.localizedExerciseName, value: units.weightText(set.kilograms) + " × \(set.reps)" + (set.rir.map { L10n.text(" · \($0) RIR") } ?? ""))
                .font(.subheadline).padding(.vertical, 3)
            }
          }
        }
        if result.effort > 0 { LabeledContent(L10n.text("How it felt"), value: "\(result.effort)/10") }
        if let run = result.run { NavigationLink(L10n.text("Route, heart rate & splits")) { ScrollView { RunSummaryView(run: run).padding(20) }.background(HybrdStyle.background) } }
        if !result.notes.isEmpty { Text(result.notes).font(.subheadline) }
      } else {
        Text(L10n.text("Your next sessions have not been moved.")).font(.subheadline)
      }
    }
    .font(.subheadline).padding(18)
    .background(HybrdStyle.terraWash, in: RoundedRectangle(cornerRadius: 20))
  }
}
