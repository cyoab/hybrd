import SwiftUI

struct ContentView: View {
  @Environment(CompanionBridge.self) private var companion

  var body: some View {
    NavigationStack {
      if let snapshot = companion.snapshot {
        List {
          Section {
            Text(snapshot.isSample ? "Sample plan" : snapshot.name + "’s plan")
              .font(.caption).foregroundStyle(.secondary)
            Text("Updated " + snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))
              .font(.caption2).foregroundStyle(.secondary)
          }
          if snapshot.workouts.isEmpty {
            Text("No upcoming sessions. Open hybrd on your iPhone to review your plan.")
              .font(.subheadline)
          }
          ForEach(snapshot.workouts) { workout in
            NavigationLink {
              WatchSessionView(workout: workout)
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                Label(workout.title, systemImage: workout.kind.symbol)
                  .font(.headline)
                Text(workout.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                  .font(.caption).foregroundStyle(.secondary)
                Text(workout.summary).font(.caption).foregroundStyle(.tint)
              }.padding(.vertical, 4)
            }
          }
        }
        .navigationTitle("hybrd")
      } else {
        ScrollView {
          VStack(spacing: 14) {
            Image(systemName: "iphone.and.arrow.forward").font(.largeTitle).foregroundStyle(.tint)
            Text("Your week, on your wrist").font(.headline)
            Text("Open hybrd on your paired iPhone, then tap Send plan to Watch in your profile.")
              .font(.footnote).foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding()
        }
        .navigationTitle("hybrd")
      }
    }
  }
}

private struct WatchSessionView: View {
  var workout: TrainingWorkout

  var body: some View {
    List {
      Section {
        Text(workout.title).font(.title3.bold())
        Text(workout.summary).foregroundStyle(.tint)
        Text(workout.prescriptionTarget).font(.footnote)
      }
      if workout.kind == .run {
        ForEach(workout.segments) { segment in
          VStack(alignment: .leading, spacing: 4) {
            Text(segment.displayTitle).font(.headline)
            Text(segment.targetSummary).foregroundStyle(.tint)
            Text(segment.cue).font(.footnote).foregroundStyle(.secondary)
          }
        }
      } else {
        ForEach(workout.exercises) { exercise in
          VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name).font(.headline)
            Text("\(exercise.sets.count) × \(exercise.sets.first?.reps ?? 0)").foregroundStyle(.tint)
            Text(exercise.note).font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
      Section {
        Text("Log completed work on your iPhone.").font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle(workout.kind.rawValue)
  }
}
