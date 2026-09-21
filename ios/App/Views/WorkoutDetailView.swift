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
      VStack(alignment: .leading, spacing: 26) {
        hero
        if let result { resultCard(result) }
        if current.kind == .run {
          RunPrescriptionView(workout: current)
        } else {
          strengthPrescription
        }
        VStack(alignment: .leading, spacing: 12) {
          Label("The purpose", systemImage: "scope").font(.headline)
          Text(current.purpose).font(.subheadline).foregroundStyle(HybrdStyle.muted)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(HybrdStyle.terraWash, in: RoundedRectangle(cornerRadius: 20))

        if result == nil && !store.hasDraft(for: current) {
          HStack {
            Button("Move session", systemImage: "calendar.badge.clock") { moving = true }
            Spacer()
            Button("Skip", systemImage: "forward.end", role: .destructive) { confirmSkip = true }
          }.font(.subheadline).padding(.vertical, 4)
        }
      }
      .padding(20)
      .frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
    .background(HybrdStyle.background)
    .toolbar(.visible, for: .navigationBar)
    .navigationTitle(current.kind == .run ? "Run session" : "Strength session")
    .navigationBarTitleDisplayMode(.inline)
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
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 8) {
        DisciplineMark(kind: current.kind, size: 8)
        Eyebrow(text: (current.isKey ? "Key session · " : current.isOptional == true ? "Optional · " : "") + current.kind.rawValue)
        Spacer()
        if let time = current.scheduledTimeLabel { Text(time).font(.caption).foregroundStyle(HybrdStyle.muted) }
      }
      VStack(alignment: .leading, spacing: 9) {
        Text(current.title).font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1)
        Text(current.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
          .font(.subheadline).foregroundStyle(HybrdStyle.muted)
      }
      HStack(spacing: 0) {
        heroMetric(value: current.kind == .run ? (Double(current.distanceMeters) / 1_000).formatted(.number.precision(.fractionLength(0...1))) : "\(current.exercises.count)",
          label: current.kind == .run ? "kilometers" : "exercises")
        Divider().frame(height: 32)
        heroMetric(value: "\(current.minutes)", label: "minutes")
        Divider().frame(height: 32)
        heroMetric(value: current.kind == .run ? effortValue : "3",
          label: current.kind == .run ? "effort" : "reps in reserve")
      }
      .padding(.vertical, 18)
      .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 18))
      .overlay(RoundedRectangle(cornerRadius: 18).stroke(HybrdStyle.line))
    }
  }

  private var effortValue: String {
    if let range = current.effort.range(of: "RPE ") {
      return String(current.effort[range.upperBound...])
    }
    return current.effort
  }

  private func heroMetric(value: String, label: String) -> some View {
    VStack(spacing: 6) {
      Text(value).font(.title3.weight(.semibold)).monospacedDigit()
      Text(label).font(.caption2).foregroundStyle(HybrdStyle.muted)
    }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
  }

  private var strengthPrescription: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Your exercises").font(.title3.weight(.semibold))
        Spacer()
        Text("\(current.exercises.reduce(0) { $0 + $1.sets.count }) SETS")
          .font(.caption2.weight(.medium)).tracking(1).foregroundStyle(HybrdStyle.muted)
      }
      ForEach(Array(current.exercises.enumerated()), id: \.element.id) { index, exercise in
        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .top, spacing: 13) {
            Text(String(format: "%02d", index + 1))
              .font(.caption.weight(.semibold)).foregroundStyle(HybrdStyle.muted)
              .frame(width: 34, height: 34)
              .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
              Text(exercise.name).font(.headline)
              Text("\(exercise.sets.count) sets × \(exercise.sets.first?.reps ?? 0) reps")
                .font(.subheadline).foregroundStyle(HybrdStyle.muted)
            }
            Spacer(minLength: 0)
          }
          HStack {
            Label("\(exercise.restSeconds) sec rest", systemImage: "timer")
            Spacer()
            Text("3 RIR")
          }.font(.caption).foregroundStyle(HybrdStyle.terraText)
          if let previous = store.previousSets(for: exercise.name).first {
            Text("Last time: \(previous.kilograms.formatted()) kg × \(previous.reps)")
              .font(.caption).foregroundStyle(HybrdStyle.muted)
          }
        }
        .padding(18)
        .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(HybrdStyle.line))
      }
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
          ForEach(result.sets) { set in
            LabeledContent(set.exerciseName, value: "\(set.kilograms.formatted()) kg × \(set.reps)").font(.caption)
          }
        }
        LabeledContent("Session effort", value: "\(result.effort)/10")
        if !result.notes.isEmpty { Text(result.notes).font(.subheadline) }
      } else {
        Text("Your next sessions have not been moved.").font(.subheadline)
      }
    }
    .font(.subheadline).padding(18)
    .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    .overlay(RoundedRectangle(cornerRadius: 20).stroke(HybrdStyle.line))
  }
}
