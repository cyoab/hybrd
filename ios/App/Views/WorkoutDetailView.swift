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

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 14) {
          Label(current.kind.rawValue.uppercased(), systemImage: current.kind.symbol)
            .font(.caption.bold()).tracking(1).foregroundStyle(.tint)
          Text(current.title).font(.largeTitle.bold())
          Text(current.summary).font(.title3.weight(.medium))
          Text(current.effort).font(.subheadline).foregroundStyle(.secondary)
          Text(current.purpose).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 12)
      } header: {
        Text(current.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
      }

      if let result = store.result(for: current) {
        Section(result.status.rawValue) {
          if result.status != .skipped {
            LabeledContent("Duration", value: "\(result.durationSeconds / 60) min")
            if let meters = result.distanceMeters {
              LabeledContent("Distance", value: String(format: "%.2f km", Double(meters) / 1_000))
            } else {
              LabeledContent("Sets logged", value: "\(result.sets.count)")
              ForEach(result.sets) { set in
                LabeledContent(set.exerciseName, value: "\(set.reps) × \(set.kilograms.formatted()) kg")
                  .font(.subheadline)
              }
            }
            LabeledContent("Session effort", value: "\(result.effort)/10")
            if !result.notes.isEmpty { Text(result.notes).font(.subheadline) }
          } else {
            Text("This session was skipped. Your next sessions have not been moved.")
          }
        }
      }

      if current.kind == .run {
        Section("Run prescription") {
          ForEach(Array(current.segments.enumerated()), id: \.element.id) { index, segment in
            HStack(alignment: .top, spacing: 14) {
              Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).padding(.top, 3)
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(segment.title).font(.headline)
                  Spacer()
                  Text("\(segment.seconds / 60) min").font(.subheadline.monospacedDigit()).foregroundStyle(.tint)
                }
                Text(segment.cue).font(.subheadline).foregroundStyle(.secondary)
              }
            }.padding(.vertical, 8)
          }
        }
      } else {
        Section("Strength prescription") {
          ForEach(current.exercises) { exercise in
            VStack(alignment: .leading, spacing: 8) {
              Text(exercise.name).font(.headline)
              Text("\(exercise.sets.count) sets × \(exercise.sets.first?.reps ?? 0) reps · 3 RIR")
                .font(.subheadline).foregroundStyle(.tint)
              Text(exercise.note).font(.caption).foregroundStyle(.secondary)
              Text("Rest \(exercise.restSeconds) sec between sets").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
          }
        }
      }

      if store.result(for: current) == nil && !store.hasDraft(for: current) {
        Section {
          Button("Move session", systemImage: "calendar.badge.clock") { moving = true }
          Button("Skip session", systemImage: "forward.end", role: .destructive) { confirmSkip = true }
        }
      }
    }
    .toolbar(.visible, for: .navigationBar)
    .navigationTitle(current.kind.rawValue)
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      if store.result(for: current) == nil {
        Button {
          logging = true
        } label: {
          Label(store.hasDraft(for: current) ? "Resume logging" : "Log session", systemImage: "play.fill")
            .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
        .background(.bar)
      }
    }
    .sheet(isPresented: $logging) { WorkoutLoggerView(draft: store.draft(for: current)) }
    .sheet(isPresented: $moving) { MoveSessionView(workout: current, expectedPlanID: store.plan.id) }
    .confirmationDialog("Skip this session?", isPresented: $confirmSkip, titleVisibility: .visible) {
      Button("Skip session", role: .destructive) { store.skip(current) }
    } message: {
      Text("It will stay in your history as skipped. We won’t stack it onto another day.")
    }
  }
}
