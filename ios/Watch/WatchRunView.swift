import SwiftUI

struct WatchRunView: View {
  @Environment(\.trainingUnits) private var units
  @Environment(RunRecorder.self) private var recorder
  @Environment(CompanionBridge.self) private var companion
  @Environment(\.isLuminanceReduced) private var luminanceReduced
  @State private var finish = false
  @State private var discard = false
  @State private var page: Page = .metrics
  private enum Page: Int { case controls, metrics, guidance }

  var body: some View {
    Group {
      if let run = recorder.recording {
        if run.isFinished { summary(run) }
        else {
          TabView(selection: $page) {
            WatchRunControlsView(run: run, busy: recorder.ending || recorder.preparing, error: recorder.errorMessage,
              togglePause: { recorder.pauseOrResume() }, markLap: { recorder.lap() }, finish: { finish = true }, discard: { discard = true })
              .tag(Page.controls)
            TimelineView(.periodic(from: .now, by: luminanceReduced ? 10 : 1)) { context in
              WatchRunMetricsView(run: run, now: context.date, pace: recorder.currentPace, gps: recorder.gpsMessage)
            }.tag(Page.metrics)
            TimelineView(.periodic(from: .now, by: luminanceReduced ? 10 : 1)) { context in
              WatchRunGuidanceView(run: run, now: context.date,
                canAdvance: !run.isPaused && !recorder.ending && !recorder.preparing) { recorder.nextInterval() }
            }.tag(Page.guidance)
          }
          .tabViewStyle(.page(indexDisplayMode: .always))
          .onChange(of: run.id) { _, _ in page = .metrics }
          .onChange(of: run.isPaused) { wasPaused, isPaused in
            if wasPaused && !isPaused { page = .metrics }
          }
          .accessibilityAction(named: "Show controls") { page = .controls }
          .accessibilityAction(named: "Show live metrics") { page = .metrics }
          .accessibilityAction(named: "Show workout guidance") { page = .guidance }
        }
      }
    }
    .navigationBarBackButtonHidden()
    .confirmationDialog("Finish your run?", isPresented: $finish, titleVisibility: .visible) {
      Button("Finish and review") { recorder.finish() }
      Button("Cancel", role: .cancel) {}
    }
    .confirmationDialog("Discard recording?", isPresented: $discard, titleVisibility: .visible) {
      Button("Discard", role: .destructive) { recorder.discard() }
    }
  }
  private func summary(_ run: RunRecording) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 13) {
        Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(WatchRunStyle.mint)
        Text("Run complete.").font(.title3.bold())
        Text(units.distanceText(run.meters, decimals: 2)).font(.system(.title, design: .rounded, weight: .bold))
        Text(RunRecording.clock(run.elapsed) + " · " + units.paceText(run.averagePace)).font(.footnote.monospacedDigit())
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
