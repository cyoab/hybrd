import SwiftUI

struct WatchRunControlsView: View {
  var run: RunRecording
  var busy: Bool
  var error: String?
  var togglePause: () -> Void
  var markLap: () -> Void
  var finish: () -> Void
  var discard: () -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        Text(run.isPaused ? "RUN PAUSED" : "RUN CONTROLS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        HStack(alignment: .top, spacing: 8) {
          control(run.isPaused ? "Resume" : "Pause", symbol: run.isPaused ? "play.fill" : "pause.fill", color: WatchRunStyle.terra, action: togglePause)
          control("Finish", symbol: "stop.fill", color: Color(red: 1, green: 0.4, blue: 0.43), action: finish)
        }
        Button("Mark lap", systemImage: "flag.fill") { markLap() }
          .disabled(run.isPaused).tint(WatchRunStyle.mint)
        if let lap = run.laps.last {
          Text(lap.title + " · " + RunRecording.clock(lap.seconds)).font(.caption2).foregroundStyle(.secondary)
        }
        if let error { Text(error).font(.caption2).foregroundStyle(.orange) }
        Button("Discard run", role: .destructive) { discard() }.font(.caption2)
      }.disabled(busy).frame(maxWidth: .infinity).padding(.horizontal, 3).padding(.bottom, 16)
      if busy { ProgressView("Saving…") }
    }
  }

  private func control(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: symbol).font(.system(size: 24, weight: .semibold))
          .frame(maxWidth: .infinity).frame(height: 60)
          .foregroundStyle(color).background(color.opacity(0.20), in: RoundedRectangle(cornerRadius: 23))
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white)
      }.contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(title == "Finish" ? "Stop and finish run" : title)
  }
}
