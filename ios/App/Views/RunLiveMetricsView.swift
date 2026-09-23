import SwiftUI

struct RunLiveMetricsView: View {
  @Environment(\.trainingUnits) private var units
  var run: RunRecording
  var now: Date
  var pace: Double?
  var gps: String
  @Environment(\.dynamicTypeSize) private var typeSize
  private var step: RunTimeline.Step? { run.step(at: now) }

  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label(run.isPaused ? L10n.text("Paused") : L10n.text("Recording on iPhone"), systemImage: run.isPaused ? "pause.fill" : "record.circle")
          Spacer()
          if let step { Text(L10n.text("\(step.id + 1) / \(RunTimeline(segments: run.workout.segments).steps.count)")) }
        }.font(.caption.weight(.semibold))
        Text(step?.segment.localizedTitle ?? L10n.text("Run at your rhythm")).font(.system(.title, design: .rounded, weight: .semibold))
        if let step {
          HStack {
            Text(step.segment.heartRateZone?.title ?? L10n.text("Your own effort")).font(.headline)
            Spacer()
            Text(L10n.text("\(RunRecording.clock(max(0, Double(step.endSeconds) - run.seconds(at: now) - run.intervalOffset))) left"))
              .font(.headline.monospacedDigit())
          }
          ProgressView(value: min(Double(step.seconds), max(0, run.seconds(at: now) + run.intervalOffset - Double(step.startSeconds))), total: Double(max(1, step.seconds)))
            .tint(HybrdStyle.terraText).accessibilityLabel(L10n.text("Current interval progress"))
          Text(step.segment.localizedCue).font(.subheadline)
          if let zone = step.segment.heartRateZone, let zones = run.zones, zones.isValid { Text(L10n.text("Target · ") + zones.label(for: zone)).font(.caption.weight(.semibold)) }
        }
      }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [RunPalette.wash(run.workout.resolvedRunType), HybrdStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.text("CURRENT PACE")).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(HybrdStyle.muted)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(units.paceNumber(run.isPaused ? nil : pace)).font(.system(size: typeSize.isAccessibilitySize ? 58 : 78, weight: .semibold, design: .rounded)).monospacedDigit()
          Text("/" + units.distance.symbol).font(.title3).foregroundStyle(HybrdStyle.muted)
        }
        Label(run.isPaused ? L10n.text("Recording paused") : gps, systemImage: "location.fill").font(.caption).foregroundStyle(HybrdStyle.muted)
      }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
      let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2)
      LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
        metric(L10n.text("DISTANCE"), units.distanceNumber(run.meters, decimals: 2), units.distance.symbol, "point.topleft.down.to.point.bottomright.curvepath")
        metric(L10n.text("ACTIVE TIME"), RunRecording.clock(run.seconds(at: now)), "", "timer")
        metric(L10n.text("AVERAGE PACE"), units.paceNumber(run.meters >= 10 ? run.seconds(at: now) * 1_000 / run.meters : nil), "/" + units.distance.symbol, "speedometer")
        metric(L10n.text("HEART RATE"), run.currentHeartRate(at: now).map { Int($0.rounded()).formatted() } ?? "—", L10n.text("bpm"), "heart.fill")
      }
      if let bpm = run.currentHeartRate(at: now), let zone = run.zone(for: bpm) { RunZoneBadge(zone: zone) }
      else if run.currentHeartRate(at: now) == nil { Text(L10n.text("Waiting for a fresh heart-rate reading. Your run keeps recording.")).font(.caption).foregroundStyle(HybrdStyle.muted) }
    }
  }
  private func metric(_ title: String, _ value: String, _ unit: String, _ icon: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon).font(.caption2.weight(.semibold)).foregroundStyle(HybrdStyle.muted)
      Text(value + (unit.isEmpty ? "" : " " + unit)).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
  }
}
