import SwiftUI

struct WatchRunView: View {
  @Environment(RunRecorder.self) private var recorder
  @Environment(CompanionBridge.self) private var companion
  @Environment(\.isLuminanceReduced) private var luminanceReduced
  @State private var finish = false
  @State private var discard = false
  @State private var page = 0

  var body: some View {
    Group {
      if let run = recorder.recording {
        if run.isFinished { summary(run) }
        else {
          TabView(selection: $page) {
            TimelineView(.periodic(from: .now, by: luminanceReduced ? 10 : 1)) { context in
              WatchRunMetricsView(run: run, now: context.date, pace: recorder.currentPace, gps: recorder.gpsMessage)
            }.tag(0)
            TimelineView(.periodic(from: .now, by: luminanceReduced ? 10 : 1)) { context in
              interval(run, at: context.date)
            }.tag(1)
            controls(run).tag(2)
          }.tabViewStyle(.verticalPage)
        }
      }
    }
    .navigationBarBackButtonHidden()
    .confirmationDialog("Finish your run?", isPresented: $finish, titleVisibility: .visible) {
      Button("Finish and review") { recorder.finish() }
    }
    .confirmationDialog("Discard recording?", isPresented: $discard, titleVisibility: .visible) {
      Button("Discard", role: .destructive) { recorder.discard() }
    }
  }
  private func interval(_ run: RunRecording, at now: Date) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        if let step = run.step(at: now) {
          Text("CURRENT INTERVAL").font(.caption2).foregroundStyle(WatchRunStyle.terra)
          Text(step.segment.title).font(.title3.bold())
          Text(RunRecording.clock(max(0, Double(step.endSeconds) - run.seconds(at: now) - run.intervalOffset)))
            .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
          Text(step.segment.heartRateZone?.title ?? "Your own effort").font(.headline).foregroundStyle(WatchRunStyle.mint)
          if let zone = step.segment.heartRateZone, let zones = run.zones, zones.isValid { Text(zones.label(for: zone)).font(.caption2) }
          Text(step.segment.cue).font(.caption2).foregroundStyle(.secondary)
          Button("Next interval", systemImage: "forward.end") { recorder.nextInterval() }.disabled(run.isPaused || recorder.ending)
        } else {
          Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(WatchRunStyle.mint)
          Text("Intervals complete").font(.headline)
          Text("Keep running at your own rhythm, or finish when you’re ready.").font(.footnote)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private func controls(_ run: RunRecording) -> some View {
    ScrollView {
      VStack(spacing: 10) {
        Button(run.isPaused ? "Resume" : "Pause", systemImage: run.isPaused ? "play.fill" : "pause.fill") { recorder.pauseOrResume() }
          .buttonStyle(.borderedProminent).tint(WatchRunStyle.terra)
        Button("Mark lap", systemImage: "flag.fill") { recorder.lap() }.disabled(run.isPaused)
        Button("Finish", systemImage: "stop.fill") { finish = true }.tint(.red)
        if let lap = run.laps.last { Text(lap.title + " · " + RunRecording.clock(lap.seconds)).font(.caption2).foregroundStyle(.secondary) }
        if let message = recorder.errorMessage { Text(message).font(.caption2).foregroundStyle(.orange) }
        Button("Discard", role: .destructive) { discard = true }.font(.caption2)
      }.disabled(recorder.ending)
      if recorder.ending { ProgressView("Saving…") }
    }
  }
  private func summary(_ run: RunRecording) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 13) {
        Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(WatchRunStyle.mint)
        Text("Run complete.").font(.title3.bold())
        Text((run.meters / 1_000).formatted(.number.precision(.fractionLength(2))) + " km").font(.system(.title, design: .rounded, weight: .bold))
        Text(RunRecording.clock(run.elapsed) + " · " + RunRecording.pace(run.averagePace) + " /km").font(.footnote.monospacedDigit())
        if let heart = run.averageHeartRate { Label("\(Int(heart.rounded())) bpm average", systemImage: "heart.fill").font(.caption) }
        if let message = run.healthSaveMessage { Text(message).font(.caption2).foregroundStyle(.secondary) }
        if let message = run.recoveryMessage { Text(message).font(.caption2).foregroundStyle(.orange) }
        if recorder.ending { ProgressView("Saving…") }
        else if run.canSave {
          Button("Save & sync", systemImage: "checkmark") {
            if companion.queueRun(run) { _ = recorder.clearAfterSaving() }
          }.buttonStyle(.borderedProminent)
          Text("Your run stays on Watch until iPhone confirms it is saved.").font(.caption2).foregroundStyle(.secondary)
        } else {
          Text("No measurable distance was captured.").font(.caption)
          Button("Discard empty run", role: .destructive) { discard = true }
        }
        if let error = recorder.errorMessage { Text(error).font(.caption2).foregroundStyle(.orange) }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
