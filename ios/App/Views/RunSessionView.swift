import SwiftUI

struct RunSessionView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(RunRecorder.self) private var recorder
  @Environment(\.dismiss) private var dismiss
  var workout: TrainingWorkout
  @State private var manual = false
  @State private var watchHelp = false
  @State private var finish = false
  @State private var discard = false
  @State private var conflict = false

  var body: some View {
    NavigationStack {
      sessionContent
      .background(HybrdStyle.background).navigationTitle(recorder.recording?.workout.title ?? workout.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) {
        Button("Minimize workout", systemImage: "chevron.down") { dismiss() }.labelStyle(.iconOnly)
      } }
      .safeAreaInset(edge: .bottom) {
        if let run = recorder.recording, !run.isFinished { controls(run) }
      }
      .confirmationDialog("Finish this run?", isPresented: $finish, titleVisibility: .visible) {
        Button("Finish and review") { recorder.finish() }
      } message: { Text("Recording will stop. Your measured time, distance, heart rate and laps will be kept for review.") }
      .confirmationDialog("Discard this recording?", isPresented: $discard, titleVisibility: .visible) {
        Button("Discard recording", role: .destructive) { recorder.discard() }
      }
      .confirmationDialog("This session already has a result", isPresented: $conflict, titleVisibility: .visible) {
        Button("Keep as a separate run") { if let run = recorder.recording { save(run, separate: true) } }
      } message: { Text("Keep both recordings only if they represent different runs.") }
      .sheet(isPresented: $watchHelp) { watchInstructions }
      .fullScreenCover(isPresented: $manual) { WorkoutLoggerView(draft: store.draft(for: workout)) }
      .sensoryFeedback(.success, trigger: recorder.cue)
      .interactiveDismissDisabled(recorder.preparing || recorder.ending)
      .onChange(of: store.result(for: workout)?.id) { _, id in if id != nil && recorder.recording == nil { dismiss() } }
    }.tint(HybrdStyle.terraText)
  }
  private var sessionContent: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          if let run = recorder.recording {
            if run.isFinished {
              RunSummaryView(run: run)
              if !recorder.ending {
                Button("Save run to hybrd", systemImage: "checkmark") { save(run) }
                  .buttonStyle(HybrdPrimaryButtonStyle()).disabled(!run.canSave)
                if !run.canSave { Text("No measurable distance was captured. You can discard this empty recording and log your run manually.").font(.subheadline).foregroundStyle(HybrdStyle.muted)
                  Button("Discard empty recording", role: .destructive) { discard = true }
                }
              }
            } else {
              TimelineView(.periodic(from: .now, by: 1)) { context in
                RunLiveMetricsView(run: run, now: context.date, pace: recorder.currentPace,
                  gps: recorder.gpsMessage)
              }
              if !run.laps.isEmpty { lapList(run) }
              if let message = run.recoveryMessage { Label(message, systemImage: "arrow.clockwise").font(.subheadline).foregroundStyle(HybrdStyle.muted) }
            }
          } else { ready }
          if let error = recorder.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(HybrdStyle.terraText)
          }
          if recorder.ending { ProgressView("Saving your measurements…").frame(maxWidth: .infinity) }
        }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
      }
  }
  private var ready: some View {
    VStack(alignment: .leading, spacing: 22) {
      Image("SessionShoe").resizable().scaledToFit().frame(height: 145).frame(maxWidth: .infinity).accessibilityHidden(true)
      Eyebrow(text: "Ready when you are")
      Text("Find your rhythm.").font(.system(.largeTitle, design: .rounded, weight: .semibold))
      Text("Pace, distance, laps, and your next interval. Keep your run in view on iPhone or take it with you on Apple Watch.")
        .foregroundStyle(HybrdStyle.muted)
      RunRhythmView(segments: workout.segments, type: workout.resolvedRunType)
      Label(workout.prescriptionTarget, systemImage: "heart.fill").foregroundStyle(HybrdStyle.terraText)
      Button { Task { await recorder.start(workout, zones: store.profile.athlete?.heartRateZones) } } label: {
        Label(recorder.preparing ? "Preparing…" : "Record on iPhone", systemImage: "play.fill")
      }.buttonStyle(HybrdPrimaryButtonStyle()).disabled(recorder.preparing)
      Button("Use Apple Watch", systemImage: "applewatch") { store.shareWithWatch(); watchHelp = true }
        .buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(recorder.preparing)
      Text("Outdoor GPS recording. Heart rate on iPhone requires a supported heart-rate sensor; Apple Watch measures it from your wrist. Permissions are requested when you start.")
        .font(.caption).foregroundStyle(HybrdStyle.muted)
      Divider()
      Button("Log a completed run manually", systemImage: "square.and.pencil") { manual = true }.disabled(recorder.preparing)
    }
  }
  private func controls(_ run: RunRecording) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        Button("Lap", systemImage: "flag") { recorder.lap() }.buttonStyle(.bordered).disabled(run.isPaused || recorder.ending)
        Button(run.isPaused ? "Resume" : "Pause", systemImage: run.isPaused ? "play.fill" : "pause.fill") { recorder.pauseOrResume() }
          .buttonStyle(HybrdPrimaryButtonStyle()).disabled(recorder.ending)
        Button("Finish", systemImage: "stop.fill") { finish = true }.buttonStyle(.bordered).disabled(recorder.ending)
      }
      HStack {
        Button("Next interval", systemImage: "forward.end") { recorder.nextInterval() }.disabled(run.isPaused || run.step(at: Date()) == nil || recorder.ending)
        Spacer()
        Button("Discard", role: .destructive) { discard = true }.disabled(recorder.ending)
      }.font(.caption)
    }.padding(16).background(HybrdStyle.surface)
  }
  private func lapList(_ run: RunRecording) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Your splits").font(.headline)
      ForEach(run.laps.suffix(5).reversed()) { lap in
        HStack { Text(lap.title); Spacer(); Text(RunRecording.clock(lap.seconds)); Text(RunRecording.pace(lap.pace) + " /km").foregroundStyle(HybrdStyle.muted) }
          .font(.subheadline.monospacedDigit())
      }
    }.padding(18).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 24))
  }
  private var watchInstructions: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 22) {
        Image(systemName: "applewatch").font(.system(size: 60)).foregroundStyle(HybrdStyle.terra)
        Text("Leave your phone behind.").font(.largeTitle.bold())
        Text("Open hybrd on your Apple Watch, choose this session, then tap Start run. Let the plan finish syncing before you leave.")
        Text("Watch records your heart rate, distance and laps independently. Finish there; your run transfers when your paired iPhone reconnects.")
        Text(store.companion.connectionMessage).font(.subheadline).foregroundStyle(HybrdStyle.muted)
        Spacer()
      }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { watchHelp = false } } }
    }.presentationDetents([.large])
  }
  private func save(_ run: RunRecording, separate: Bool = false) {
    if store.saveRecordedRun(run, asSeparate: separate) { if recorder.clearAfterSaving() { dismiss() } }
    else if store.state.results.contains(where: { $0.logicalWorkoutID == run.workout.logicalID }) { conflict = true }
  }
}
