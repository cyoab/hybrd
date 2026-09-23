import SwiftUI

struct WatchRunControlsView: View {
  @Environment(\.trainingUnits) private var units
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
        Text(run.isPaused ? L10n.text("RUN PAUSED") : L10n.text("RUN CONTROLS")).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        HStack(alignment: .top, spacing: 8) {
          control(run.isPaused ? L10n.text("Resume") : L10n.text("Pause"), symbol: run.isPaused ? "play.fill" : "pause.fill", color: WatchRunStyle.terra, action: togglePause)
          control(L10n.text("Finish"), symbol: "stop.fill", color: Color(red: 1, green: 0.4, blue: 0.43), accessibility: L10n.text("Stop and finish run"), action: finish)
        }
        Button(L10n.text("Mark lap"), systemImage: "flag.fill") { markLap() }
          .disabled(run.isPaused).tint(WatchRunStyle.mint)
        if let lap = run.laps.last {
          Text(units.lapTitle(lap) + " · " + units.distanceText(lap.meters, decimals: 2) + " · " + RunRecording.clock(lap.seconds)).font(.caption2).foregroundStyle(.secondary)
        }
        if let error { Text(error).font(.caption2).foregroundStyle(.orange) }
        Button(L10n.text("Discard run"), role: .destructive) { discard() }.font(.caption2)
      }.disabled(busy).frame(maxWidth: .infinity).padding(.horizontal, 3).padding(.bottom, 16)
      if busy { ProgressView(L10n.text("Saving…")) }
    }
  }

  private func control(_ title: String, symbol: String, color: Color, accessibility: String? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: symbol).font(.system(size: 24, weight: .semibold))
          .frame(maxWidth: .infinity).frame(height: 60)
          .foregroundStyle(color).background(color.opacity(0.20), in: RoundedRectangle(cornerRadius: 23))
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      }.contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityLabel(accessibility ?? title)
  }
}
