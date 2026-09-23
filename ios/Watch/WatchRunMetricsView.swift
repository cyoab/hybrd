import SwiftUI

struct WatchRunMetricsView: View {
  @Environment(\.trainingUnits) private var units
  @Environment(\.dynamicTypeSize) private var typeSize
  var run: RunRecording
  var now: Date
  var pace: Double?
  var gps: String
  @ScaledMetric(relativeTo: .title) private var paceSize = 38
  @ScaledMetric(relativeTo: .title2) private var metricSize = 33
  @ScaledMetric(relativeTo: .title2) private var heartSize = 29
  @ScaledMetric(relativeTo: .caption2) private var labelSize = 10
  private var metrics: RunLiveMetrics { RunLiveMetrics(run: run, at: now, currentPace: pace) }
  private var target: HeartRateZone? { run.step(at: now)?.segment.heartRateZone }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 7) {
        metricPair {
          metric(metrics.paceIsLast ? L10n.text("LAST PACE") : L10n.text("PACE"),
            value: units.paceNumber(metrics.pace), unit: "/" + units.distance.symbol,
            color: metrics.paceIsLast ? .yellow : .white, size: paceSize,
            accessibility: metrics.paceIsLast ? L10n.text("Last recorded pace") : L10n.text("Current pace"),
            spokenValue: metrics.pace.map { L10n.text("\(units.paceNumber($0)) per \(units.distance.singular)") } ?? L10n.text("Unavailable"))
          metric(L10n.text("AVG PACE"), value: units.paceNumber(metrics.averagePace), unit: "/" + units.distance.symbol,
            color: WatchRunStyle.mint, size: metricSize,
            accessibility: L10n.text("Average pace"),
            spokenValue: metrics.averagePace.map { L10n.text("\(units.paceNumber($0)) per \(units.distance.singular)") } ?? L10n.text("Unavailable"))
        }
        VStack(spacing: 3) {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "heart.fill").font(.caption2).foregroundStyle(WatchRunStyle.terra)
            Text(metrics.heartRate.map { Int($0.rounded()).formatted() } ?? "—")
              .font(.system(size: heartSize, weight: .bold, design: .rounded)).monospacedDigit()
            Text(L10n.text("bpm")).font(.system(size: labelSize)).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(metrics.zone?.title ?? L10n.text("Zone —"))
              .font(.system(size: labelSize + 1, weight: .bold, design: .rounded))
              .foregroundStyle(metrics.zone.map(WatchRunStyle.zoneColor) ?? .white.opacity(0.65))
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(L10n.text("Heart rate"))
          .accessibilityValue(metrics.heartRate.map { L10n.text("\(Int($0.rounded())) beats per minute, ") + (metrics.zone?.title ?? L10n.text("zone unavailable")) } ?? L10n.text("Unavailable"))
          WatchHeartRateZoneView(current: metrics.zone, target: target)
        }
        metricPair {
          metric(L10n.text("DISTANCE"), value: units.distanceNumber(run.meters, decimals: 2), unit: units.distance.symbol,
            color: .white, size: metricSize, accessibility: L10n.text("Distance covered"),
            spokenValue: units.distanceText(run.meters, decimals: 2))
          if let remaining = metrics.remainingMeters {
            metric(L10n.text("REMAINING"), value: units.distanceNumber(remaining, decimals: 2), unit: units.distance.symbol,
              color: WatchRunStyle.terra, size: metricSize, accessibility: L10n.text("Distance remaining"),
              spokenValue: units.distanceText(remaining, decimals: 2))
          } else {
            metric(L10n.text("TIME LEFT"), value: metrics.remainingSeconds.map(RunRecording.clock) ?? "—", unit: "",
              color: WatchRunStyle.terra, size: metricSize, accessibility: L10n.text("Workout time remaining"),
              spokenValue: metrics.remainingSeconds.map(RunRecording.clock) ?? L10n.text("No target"))
          }
        }
        footer
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4).padding(.bottom, 3)
    }
    .scrollIndicators(.hidden)
  }

  @ViewBuilder private func metricPair<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    if typeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 8, content: content)
    } else {
      HStack(alignment: .top, spacing: 8, content: content)
    }
  }

  private func metric(_ label: String, value: String, unit: String, color: Color, size: CGFloat,
    accessibility: String, spokenValue: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(label).font(.system(size: labelSize, weight: .semibold))
        if !unit.isEmpty { Text(unit).font(.system(size: labelSize - 1)) }
      }.foregroundStyle(color.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.8)
      Text(value).font(.system(size: size, weight: .bold, design: .rounded))
        .monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibility).accessibilityValue(spokenValue)
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Image(systemName: run.isPaused ? "pause.fill" : "timer").accessibilityHidden(true)
        Text(run.isPaused ? L10n.text("PAUSED") : RunRecording.clock(run.seconds(at: now)))
          .monospacedDigit()
        Spacer(minLength: 3)
        if let target { Text(L10n.text("Target \(target.shortTitle)")) }
      }
      .font(.system(size: labelSize, weight: .medium)).foregroundStyle(.secondary)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(run.isPaused ? L10n.text("Recording paused") : L10n.text("Active time, \(RunRecording.clock(run.seconds(at: now)))"))
      if run.zones?.isValid != true {
        Text(L10n.text("Set your zones on iPhone")).font(.caption2).foregroundStyle(.secondary)
      }
      if metrics.pace == nil && !run.isPaused {
        Text(gps).font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}
