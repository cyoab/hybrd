import SwiftUI

struct RunSessionView: View {
  @Environment(\.trainingUnits) private var units
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
      .background(HybrdStyle.background).navigationTitle(recorder.recording?.workout.localizedTitle ?? workout.localizedTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) {
        Button(L10n.text("Minimize workout"), systemImage: "chevron.down") { dismiss() }.labelStyle(.iconOnly)
      } }
      .safeAreaInset(edge: .bottom) {
        if let run = recorder.recording, !run.isFinished { controls(run) }
      }
      .confirmationDialog(L10n.text("Finish this run?"), isPresented: $finish, titleVisibility: .visible) {
        Button(L10n.text("Finish and review")) { recorder.finish() }
      } message: { Text(L10n.text("Recording will stop. Your measured time, distance, heart rate and laps will be kept for review.")) }
      .confirmationDialog(L10n.text("Discard this recording?"), isPresented: $discard, titleVisibility: .visible) {
        Button(L10n.text("Discard recording"), role: .destructive) { recorder.discard() }
      }
      .confirmationDialog(L10n.text("This session already has a result"), isPresented: $conflict, titleVisibility: .visible) {
        Button(L10n.text("Keep as a separate run")) { if let run = recorder.recording { save(run, separate: true) } }
      } message: { Text(L10n.text("Keep both recordings only if they represent different runs.")) }
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
                Button(L10n.text("Save run to hybrd"), systemImage: "checkmark") { save(run) }
                  .buttonStyle(HybrdPrimaryButtonStyle()).disabled(!run.canSave || !store.isBackendConnected)
                if !store.isBackendConnected { Text(L10n.text("Sign in to save your training.")).font(.subheadline).foregroundStyle(HybrdStyle.muted) }
                if run.canSave { Button(L10n.text("Discard"), role: .destructive) { discard = true } }
                if !run.canSave { Text(L10n.text("No measurable distance was captured. You can discard this empty recording and log your run manually.")).font(.subheadline).foregroundStyle(HybrdStyle.muted)
                  Button(L10n.text("Discard empty recording"), role: .destructive) { discard = true }
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
          if recorder.ending { ProgressView(L10n.text("Saving your measurements…")).frame(maxWidth: .infinity) }
        }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
      }
  }
  private var ready: some View {
    VStack(alignment: .leading, spacing: 22) {
      Image("SessionShoe").resizable().scaledToFit().frame(height: 145).frame(maxWidth: .infinity).accessibilityHidden(true)
      Eyebrow(text: L10n.text("Ready when you are"))
      Text(L10n.text("Find your rhythm.")).font(.system(.largeTitle, design: .rounded, weight: .semibold))
      Text(L10n.text("Pace, distance, laps, and your next interval. Keep your run in view on iPhone or take it with you on Apple Watch."))
        .foregroundStyle(HybrdStyle.muted)
      RunRhythmView(segments: workout.segments, type: workout.resolvedRunType)
      Label(workout.prescriptionTarget, systemImage: "heart.fill").foregroundStyle(HybrdStyle.terraText)
      Button { Task { await recorder.start(workout, zones: store.profile.athlete?.heartRateZones, units: units) } } label: {
        Label(recorder.preparing ? L10n.text("Preparing…") : L10n.text("Record on iPhone"), systemImage: "play.fill")
      }.buttonStyle(HybrdPrimaryButtonStyle()).disabled(recorder.preparing)
      Button(L10n.text("Use Apple Watch"), systemImage: "applewatch") { store.shareWithWatch(); watchHelp = true }
        .buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(recorder.preparing)
      Text(L10n.text("Outdoor GPS recording. Heart rate on iPhone requires a supported heart-rate sensor; Apple Watch measures it from your wrist. Permissions are requested when you start."))
        .font(.caption).foregroundStyle(HybrdStyle.muted)
      Divider()
      Button { manual = true } label: {
        Label(L10n.text("Log a completed run manually"), systemImage: "square.and.pencil")
          .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }.buttonStyle(.plain).disabled(recorder.preparing)
    }
  }
  private func controls(_ run: RunRecording) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        Button(L10n.text("Lap"), systemImage: "flag") { recorder.lap() }.buttonStyle(.bordered).disabled(run.isPaused || recorder.ending)
        Button(run.isPaused ? L10n.text("Resume") : L10n.text("Pause"), systemImage: run.isPaused ? "play.fill" : "pause.fill") { recorder.pauseOrResume() }
          .buttonStyle(HybrdPrimaryButtonStyle()).disabled(recorder.ending)
        Button(L10n.text("Finish"), systemImage: "stop.fill") { finish = true }.buttonStyle(.bordered).disabled(recorder.ending)
      }
      HStack {
        Button(L10n.text("Next interval"), systemImage: "forward.end") { recorder.nextInterval() }.disabled(run.isPaused || run.step(at: Date()) == nil || recorder.ending)
        Spacer()
        Button(L10n.text("Discard"), role: .destructive) { discard = true }.disabled(recorder.ending)
      }.font(.caption)
    }.padding(16).background(HybrdStyle.surface)
  }
  private func lapList(_ run: RunRecording) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("Your splits")).font(.headline)
      ForEach(run.laps.suffix(5).reversed()) { lap in
        HStack { VStack(alignment: .leading, spacing: 3) { Text(units.lapTitle(lap)); Text(units.distanceText(lap.meters, decimals: 2)).font(.caption).foregroundStyle(HybrdStyle.muted) }; Spacer(); Text(RunRecording.clock(lap.seconds)); Text(units.paceText(lap.pace)).foregroundStyle(HybrdStyle.muted) }
          .font(.subheadline.monospacedDigit())
      }
    }.padding(18).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 24))
  }
  private var watchInstructions: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 22) {
        Image(systemName: "applewatch").font(.system(size: 60)).foregroundStyle(HybrdStyle.terra)
        Text(L10n.text("Leave your phone behind.")).font(.largeTitle.bold())
        Text(L10n.text("Open hybrd on your Apple Watch, choose this session, then tap Start run. Let the plan finish syncing before you leave."))
        Text(L10n.text("Watch records your heart rate, distance and laps independently. Finish there; your run transfers when your paired iPhone reconnects."))
        Text(store.companion.connectionMessage).font(.subheadline).foregroundStyle(HybrdStyle.muted)
        Spacer()
      }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { watchHelp = false } } }
    }.presentationDetents([.large])
  }
  private func save(_ run: RunRecording, separate: Bool = false) {
    if store.saveRecordedRun(run, asSeparate: separate) { if recorder.clearAfterSaving() { dismiss() } }
    else if store.state.results.contains(where: { $0.logicalWorkoutID == run.workout.logicalID }) { conflict = true }
  }
}
