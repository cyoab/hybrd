import SwiftUI

struct WorkoutDetailView: View {
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
      VStack(alignment: .leading, spacing: 28) {
        hero
        if let result { resultCard(result) }

        HStack(alignment: .top, spacing: 14) {
          Image(systemName: "scope").font(.title3).foregroundStyle(HybrdStyle.terraText)
            .padding(.top, 2).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 7) {
            Text("Why this session").font(.subheadline.weight(.semibold))
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
    .background(HybrdStyle.background)
    .toolbar(.visible, for: .navigationBar)
    .navigationTitle(current.kind == .run ? "Run session" : "Strength session")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if result == nil && !store.hasDraft(for: current) {
        ToolbarItem(placement: .primaryAction) {
          Menu("Session options", systemImage: "ellipsis") {
            Button("Move session", systemImage: "calendar.badge.clock") { moving = true }
            Button("Skip session", systemImage: "forward.end", role: .destructive) { confirmSkip = true }
          }.labelStyle(.iconOnly)
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if result == nil {
        Button { logging = true } label: {
          Label(store.hasDraft(for: current) ? "Continue session" : (current.kind == .strength ? "Start workout" : "Log run"),
            systemImage: current.kind == .strength ? "play.fill" : "square.and.pencil")
        }
        .buttonStyle(HybrdPrimaryButtonStyle())
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(HybrdStyle.surface)
        .overlay(alignment: .top) { Rectangle().fill(HybrdStyle.line).frame(height: 0.5) }
      }
    }
    .fullScreenCover(isPresented: $logging) { WorkoutLoggerView(draft: store.draft(for: current)) }
    .sheet(isPresented: $moving) { MoveSessionView(workout: current, expectedPlanID: store.plan.id) }
    .confirmationDialog("Skip this session?", isPresented: $confirmSkip, titleVisibility: .visible) {
      Button("Skip session", role: .destructive) { store.skip(current) }
    } message: {
      Text("It will stay in your history as skipped. We won’t stack it onto another day.")
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          DisciplineMark(kind: current.kind, size: 8)
          Eyebrow(text: (current.isKey ? "Key session · " : current.isOptional == true ? "Optional · " : "") + current.kind.rawValue)
        }
        Text(current.title)
          .font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1)
          .fixedSize(horizontal: false, vertical: true)
        Text(current.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
          + (current.scheduledTimeLabel.map { " · " + $0 } ?? ""))
          .font(.subheadline).foregroundStyle(HybrdStyle.muted)
      }

      SessionInfographicView(workout: current)
    }
  }

  private func resultCard(_ result: WorkoutResult) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(result.status.rawValue, systemImage: result.status == .skipped ? "forward.end" : "checkmark")
        .font(.headline).foregroundStyle(HybrdStyle.terraText)
      if result.status != .skipped {
        LabeledContent("Actual duration", value: "\(result.durationSeconds / 60) min")
        if let meters = result.distanceMeters {
          LabeledContent("Actual distance", value: (Double(meters) / 1_000).formatted() + " km")
        } else {
          LabeledContent("Sets completed", value: "\(result.sets.count)")
          DisclosureGroup("Recorded sets") {
            ForEach(result.sets) { set in
              LabeledContent(set.exerciseName, value: "\(set.kilograms.formatted()) kg × \(set.reps)")
                .font(.subheadline).padding(.vertical, 3)
            }
          }
        }
        LabeledContent("Session effort", value: "\(result.effort)/10")
        if !result.notes.isEmpty { Text(result.notes).font(.subheadline) }
      } else {
        Text("Your next sessions have not been moved.").font(.subheadline)
      }
    }
    .font(.subheadline).padding(18)
    .background(HybrdStyle.terraWash, in: RoundedRectangle(cornerRadius: 20))
  }
}
