import SwiftUI

struct ContentView: View {
  @Environment(CompanionBridge.self) private var companion
  @Environment(RunRecorder.self) private var recorder
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack {
      if recorder.recording != nil {
        WatchRunView()
      } else {
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
                VStack(alignment: .leading, spacing: 5) {
                  Label(workout.title, systemImage: workout.kind.symbol).font(.headline)
                  Text(workout.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.caption2).foregroundStyle(.secondary)
                  Text(workout.prescriptionTarget).font(.caption).foregroundStyle(WatchRunStyle.terra)
                }.padding(.vertical, 4)
              }
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
    .tint(WatchRunStyle.terra)
    .onChange(of: scenePhase) { _, phase in if phase == .active { companion.retryTransfers() } }
  }
}

private struct WatchSessionReadyView: View {
  var workout: TrainingWorkout
  @Environment(CompanionBridge.self) private var companion
  @Environment(RunRecorder.self) private var recorder
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text(workout.title).font(.title3.bold())
        Text(workout.summary).font(.footnote).foregroundStyle(.secondary)
        if workout.kind == .run {
          Label(workout.prescriptionTarget, systemImage: "heart.fill").font(.footnote).foregroundStyle(WatchRunStyle.terra)
          Button(recorder.preparing ? "Preparing…" : "Start run", systemImage: "play.fill") {
            Task { await recorder.start(workout, zones: companion.snapshot?.heartRateZones) }
          }.buttonStyle(.borderedProminent).disabled(recorder.preparing)
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
        if let error = recorder.errorMessage { Text(error).font(.caption2).foregroundStyle(.orange) }
      }.padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
    }.navigationTitle(workout.kind.rawValue)
  }
}

enum WatchRunStyle {
  static func zoneColor(_ zone: HeartRateZone) -> Color {
    switch zone { case .one: .cyan; case .two: mint; case .three: .yellow; case .four: terra; case .five: .purple }
  }
  static let terra = Color(red: 1, green: 0.48, blue: 0.3)
  static let mint = Color(red: 0.45, green: 0.85, blue: 0.68)
}
