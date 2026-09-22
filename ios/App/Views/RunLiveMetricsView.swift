import SwiftUI

struct RunLiveMetricsView: View {
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
          Label(run.isPaused ? "Paused" : "Recording on iPhone", systemImage: run.isPaused ? "pause.fill" : "record.circle")
          Spacer()
          if let step { Text("\(step.id + 1) / \(RunTimeline(segments: run.workout.segments).steps.count)") }
        }.font(.caption.weight(.semibold))
        Text(step?.segment.title ?? "Run at your rhythm").font(.system(.title, design: .rounded, weight: .semibold))
        if let step {
          HStack {
            Text(step.segment.heartRateZone?.title ?? "Your own effort").font(.headline)
            Spacer()
            Text(RunRecording.clock(max(0, Double(step.endSeconds) - run.seconds(at: now) - run.intervalOffset)) + " left")
              .font(.headline.monospacedDigit())
          }
          ProgressView(value: min(Double(step.seconds), max(0, run.seconds(at: now) + run.intervalOffset - Double(step.startSeconds))), total: Double(max(1, step.seconds)))
            .tint(HybrdStyle.terraText).accessibilityLabel("Current interval progress")
          Text(step.segment.cue).font(.subheadline)
          if let zone = step.segment.heartRateZone, let zones = run.zones, zones.isValid { Text("Target · " + zones.label(for: zone)).font(.caption.weight(.semibold)) }
        }
      }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [RunPalette.wash(run.workout.resolvedRunType), HybrdStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
      VStack(alignment: .leading, spacing: 8) {
        Text("CURRENT PACE").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(HybrdStyle.muted)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(RunRecording.pace(run.isPaused ? nil : pace)).font(.system(size: typeSize.isAccessibilitySize ? 58 : 78, weight: .semibold, design: .rounded)).monospacedDigit()
          Text("/km").font(.title3).foregroundStyle(HybrdStyle.muted)
        }
        Label(run.isPaused ? "Recording paused" : gps, systemImage: "location.fill").font(.caption).foregroundStyle(HybrdStyle.muted)
      }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
      let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2)
      LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
        metric("DISTANCE", (run.meters / 1_000).formatted(.number.precision(.fractionLength(2))), "km", "point.topleft.down.to.point.bottomright.curvepath")
        metric("ACTIVE TIME", RunRecording.clock(run.seconds(at: now)), "", "timer")
        metric("AVERAGE PACE", RunRecording.pace(run.meters >= 10 ? run.seconds(at: now) * 1_000 / run.meters : nil), "/km", "speedometer")
        metric("HEART RATE", run.currentHeartRate(at: now).map { Int($0.rounded()).formatted() } ?? "—", "bpm", "heart.fill")
      }
      if let bpm = run.currentHeartRate(at: now), let zone = run.zone(for: bpm) { RunZoneBadge(zone: zone) }
      else if run.currentHeartRate(at: now) == nil { Text("Waiting for a fresh heart-rate reading. Your run keeps recording.").font(.caption).foregroundStyle(HybrdStyle.muted) }
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
