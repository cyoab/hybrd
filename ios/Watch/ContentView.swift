import SwiftUI

struct ContentView: View {
  @Environment(CompanionBridge.self) private var companion
  @Environment(RunRecorder.self) private var recorder
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    // The recording owns its navigation stack. Changing only a stack's root
    // leaves an already-pushed session detail covering the live workout.
    Group {
      if recorder.recording != nil {
        NavigationStack { WatchRunView() }
      } else {
        NavigationStack {
          workoutList
        }
      }
    }
    .tint(WatchRunStyle.terra)
    .onChange(of: scenePhase) { _, phase in if phase == .active { companion.retryTransfers() } }
  }

  private var workoutList: some View {
    List {
      if companion.queuedRunCount > 0 {
        Section {
          Label("\(companion.queuedRunCount) run(s) saved on Watch", systemImage: "checkmark.seal")
          Text("Waiting for iPhone confirmation").font(.caption2).foregroundStyle(.secondary)
          Button("Retry transfer") { companion.retryTransfers() }
        }
      }
      if let snapshot = companion.snapshot {
        Section {
          Text(snapshot.isSample ? "Sample plan" : snapshot.name + "’s plan").font(.caption)
          Text("Updated " + snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption2).foregroundStyle(.secondary)
        }
        ForEach(snapshot.workouts) { workout in
          NavigationLink { WatchSessionReadyView(workout: workout) } label: {
            WatchWorkoutCardView(workout: workout)
          }
          .listRowBackground(RoundedRectangle(cornerRadius: 20).fill(
            WatchRunStyle.workoutColor(workout).opacity(0.16).gradient))
        }
        if snapshot.workouts.isEmpty { Text("No upcoming sessions. Choose a run on iPhone, then send your plan to Watch.").font(.footnote) }
      } else {
        Section {
          Image(systemName: "iphone.and.arrow.forward").font(.largeTitle).foregroundStyle(WatchRunStyle.terra)
          Text("Your run, on your wrist").font(.headline)
          Text("Open hybrd on your paired iPhone, then send your plan from Athlete. Once synced, you can run without your phone.").font(.footnote).foregroundStyle(.secondary)
        }
      }
    }.navigationTitle("hybrd")
  }
}

private struct WatchSessionReadyView: View {
  var workout: TrainingWorkout
  @Environment(CompanionBridge.self) private var companion
  @Environment(RunRecorder.self) private var recorder
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        WatchWorkoutCardView(workout: workout)
          .padding(10)
          .background(WatchRunStyle.workoutColor(workout).opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
        if workout.kind == .run {
          Button(recorder.preparing ? "Preparing…" : "Start run", systemImage: "play.fill") {
            Task { await recorder.start(workout, zones: companion.snapshot?.heartRateZones, units: companion.snapshot?.units ?? .metric) }
          }.buttonStyle(.borderedProminent).disabled(recorder.preparing)
          if let error = recorder.errorMessage {
            Text(error).font(.caption2).foregroundStyle(.orange)
          }
          Text("GPS, heart rate and laps record on this Watch. Your phone can stay behind.").font(.caption2).foregroundStyle(.secondary)
          ForEach(workout.segments) { segment in
            VStack(alignment: .leading, spacing: 3) {
              Text(segment.displayTitle).font(.footnote.weight(.semibold))
              Text(segment.targetSummary).font(.caption2).foregroundStyle(.secondary)
            }
          }
        } else {
          Text("Use iPhone to enter weight, reps and RIR. Your prescription is here for a quick glance.").font(.footnote).foregroundStyle(.secondary)
          ForEach(workout.exercises) { exercise in
            VStack(alignment: .leading, spacing: 4) {
              Text(exercise.name).font(.headline)
              Text("\(exercise.sets.count) sets · \(exercise.sets.first?.reps ?? 0) reps").font(.caption)
              Text(exercise.note).font(.caption2).foregroundStyle(.secondary)
            }
          }
        }
      }.padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
    }.navigationTitle(workout.kind.rawValue)
  }
}
