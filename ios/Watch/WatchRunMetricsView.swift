import SwiftUI

struct WatchRunMetricsView: View {
  var run: RunRecording
  var now: Date
  var pace: Double?
  var gps: String
  @ScaledMetric(relativeTo: .largeTitle) private var paceSize = 42
  private var heartRate: Double? { run.currentHeartRate(at: now) }
  private var zone: HeartRateZone? { heartRate.flatMap(run.zone) }
  private var target: HeartRateZone? { run.step(at: now)?.segment.heartRateZone }
  private var shownPace: Double? { run.isPaused ? nil : pace }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 5) {
        Text(run.isPaused ? "PAUSED" : run.step(at: now)?.segment.title.uppercased() ?? "RUNNING")
          .font(.caption2.weight(.bold)).foregroundStyle(WatchRunStyle.terra).lineLimit(2)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(RunRecording.pace(shownPace)).font(.system(size: paceSize, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
          VStack(alignment: .leading, spacing: 0) {
            Text("PACE").font(.system(size: 9, weight: .semibold))
            Text("/km").font(.caption2)
          }.foregroundStyle(.secondary)
        }.accessibilityElement(children: .ignore)
          .accessibilityLabel("Current pace")
          .accessibilityValue(shownPace.map { RunRecording.pace($0) + " per kilometer" } ?? "Unavailable")
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Image(systemName: "heart.fill").font(.caption).foregroundStyle(WatchRunStyle.terra)
          Text(heartRate.map { Int($0.rounded()).formatted() } ?? "—")
            .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
          Text("bpm").font(.caption2).foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Text(zone?.shortTitle ?? "—").font(.headline).foregroundStyle(zone.map(WatchRunStyle.zoneColor) ?? .secondary)
        }.accessibilityElement(children: .ignore)
          .accessibilityLabel("Heart rate")
          .accessibilityValue(heartRate.map { "\(Int($0.rounded())) beats per minute, " + (zone?.title ?? "zone unavailable") } ?? "Unavailable")
        WatchHeartRateZoneView(current: zone, target: target)
        HStack(alignment: .firstTextBaseline) {
          Text(RunRecording.clock(run.seconds(at: now))).foregroundStyle(.yellow)
            .accessibilityLabel("Active time, " + RunRecording.clock(run.seconds(at: now)))
          Spacer(minLength: 3)
          Text((run.meters / 1_000).formatted(.number.precision(.fractionLength(2))) + " km")
            .accessibilityLabel("Distance, " + (run.meters / 1_000).formatted(.number.precision(.fractionLength(2))) + " kilometers")
        }.font(.system(.footnote, design: .rounded, weight: .semibold)).monospacedDigit().padding(.top, 2)
        if let target {
          Text("Target " + target.shortTitle + (run.zones.flatMap { $0.isValid ? " · " + $0.label(for: target) : nil } ?? ""))
            .font(.caption2).foregroundStyle(WatchRunStyle.zoneColor(target))
        }
        if run.zones?.isValid != true { Text("Set your zones on iPhone").font(.caption2).foregroundStyle(.secondary) }
        if gps != "GPS connected" && !run.isPaused { Text(gps).font(.caption2).foregroundStyle(.secondary) }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 5).padding(.bottom, 10)
    }
  }
}
