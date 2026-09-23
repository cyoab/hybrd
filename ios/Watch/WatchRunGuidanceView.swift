import SwiftUI

struct WatchRunGuidanceView: View {
  var run: RunRecording
  var now: Date
  var canAdvance: Bool
  var advance: () -> Void
  private var guidance: RunGuidance { RunGuidance(run: run, at: now) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if let step = guidance.current {
          HStack(alignment: .firstTextBaseline) {
            Text(step.segment.localizedTitle).font(.caption.weight(.semibold))
            Spacer(minLength: 3)
            Text(RunRecording.clock(guidance.remaining)).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
              .foregroundStyle(WatchRunStyle.terra)
          }.accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.text("\(step.segment.localizedTitle), \(RunRecording.clock(guidance.remaining)) remaining"))
          ProgressView(value: guidance.fraction).tint(WatchRunStyle.terra)
            .accessibilityLabel(L10n.text("Current interval progress"))
          if let next = guidance.next {
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Label(L10n.text("UP NEXT"), systemImage: "arrow.right").foregroundStyle(WatchRunStyle.mint)
                Spacer(minLength: 0)
                Text("\(next.id + 1)/\(guidance.steps.count)").foregroundStyle(.secondary)
              }.font(.caption2.weight(.bold))
              Text(next.segment.localizedTitle).font(.title3.bold())
              Text(next.segment.targetSummary).font(.caption2)
              if let repetitions = next.segment.repetitions, repetitions > 1 {
                Text(L10n.text("Repeat \(next.repetition) of \(repetitions)")).font(.caption2).foregroundStyle(.secondary)
              }
              Text(next.segment.localizedCue).font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
              .background(WatchRunStyle.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
          } else {
            Label(L10n.text("Final interval"), systemImage: "flag.checkered").font(.headline).foregroundStyle(WatchRunStyle.mint)
            target(step)
            Text(step.segment.localizedCue).font(.caption2).foregroundStyle(.secondary)
          }
          Button(L10n.text("Next interval"), systemImage: "forward.end") { advance() }.disabled(!canAdvance)
            .accessibilityHint(L10n.text("Skips to the next prescribed step. Recorded time and distance stay unchanged."))
        } else {
          Image(systemName: guidance.steps.isEmpty ? "figure.run" : "checkmark.seal.fill")
            .font(.largeTitle).foregroundStyle(WatchRunStyle.mint).accessibilityHidden(true)
          Text(guidance.steps.isEmpty ? L10n.text("Your own rhythm") : L10n.text("Intervals complete")).font(.headline)
          Text(L10n.text("Keep running, or swipe to controls to finish when you’re ready.")).font(.caption2).foregroundStyle(.secondary)
        }
        Divider()
        Text(L10n.text("THE WORKOUT")).font(.caption2.weight(.bold)).foregroundStyle(WatchRunStyle.terra)
        Text(run.workout.localizedTitle).font(.headline)
        Text(run.workout.localizedPurpose).font(.caption2).foregroundStyle(.secondary)
        if !guidance.steps.isEmpty {
          WatchRunSequenceView(steps: guidance.steps, currentID: guidance.current?.id).frame(height: 30)
          ForEach(run.workout.segments) { segment in
            HStack(alignment: .top, spacing: 6) {
              Capsule().fill(segment.heartRateZone.map(WatchRunStyle.zoneColor) ?? .gray).frame(width: 3, height: 25)
              VStack(alignment: .leading, spacing: 2) {
                Text(segment.displayTitle).font(.caption.weight(.semibold))
                Text(segment.targetSummary).font(.caption2).foregroundStyle(.secondary)
              }
            }.accessibilityElement(children: .combine)
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 5).padding(.bottom, 16)
    }
  }

  @ViewBuilder private func target(_ step: RunTimeline.Step) -> some View {
    if let zone = step.segment.heartRateZone {
      Text(L10n.text("Target \(zone.title)")).font(.caption.weight(.semibold)).foregroundStyle(WatchRunStyle.zoneColor(zone))
      if let zones = run.zones, zones.isValid { Text(zones.label(for: zone)).font(.caption2).foregroundStyle(.secondary) }
    }
    if let repetitions = step.segment.repetitions, repetitions > 1 {
      Text(L10n.text("Repeat \(step.repetition) of \(repetitions)")).font(.caption2).foregroundStyle(.secondary)
    }
  }
}
