import SwiftUI

struct WatchRunMetricsView: View {
  var run: RunRecording
  var now: Date
  var pace: Double?
  var gps: String
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(run.isPaused ? "PAUSED" : run.step(at: now)?.segment.title.uppercased() ?? "RUNNING")
            .font(.caption2.weight(.bold)).foregroundStyle(WatchRunStyle.terra).lineLimit(2)
          Spacer(minLength: 0)
          if run.isPaused { Image(systemName: "pause.fill").foregroundStyle(.yellow) }
        }
        Text(RunRecording.clock(run.seconds(at: now))).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(.yellow)
          .accessibilityLabel("Active time, " + RunRecording.clock(run.seconds(at: now)))
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(RunRecording.pace(run.isPaused ? nil : pace)).font(.system(size: 43, weight: .bold, design: .rounded)).monospacedDigit()
          Text("/km").font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine).accessibilityLabel("Current pace, " + RunRecording.pace(pace) + " per kilometer")
        HStack(alignment: .firstTextBaseline) {
          Text((run.meters / 1_000).formatted(.number.precision(.fractionLength(2))) + " km").font(.headline.monospacedDigit())
          Spacer(minLength: 3)
          Label(run.currentHeartRate(at: now).map { Int($0.rounded()).formatted() } ?? "—", systemImage: "heart.fill")
            .font(.headline.monospacedDigit()).foregroundStyle(WatchRunStyle.terra)
            .accessibilityLabel("Heart rate, " + (run.currentHeartRate(at: now).map { Int($0.rounded()).formatted() + " beats per minute" } ?? "unavailable"))
        }
        if let bpm = run.currentHeartRate(at: now), let zone = run.zone(for: bpm) {
          Text(zone.title).font(.caption2).foregroundStyle(WatchRunStyle.zoneColor(zone))
        }
        Text(run.isPaused ? "Swipe for controls" : gps).font(.system(.caption2)).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 5)
    }
  }
}
