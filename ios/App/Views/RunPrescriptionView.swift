import SwiftUI

struct RunPrescriptionView: View {
  @Environment(\.trainingUnits) private var units
  var workout: TrainingWorkout
  private var timeline: RunTimeline { RunTimeline(segments: workout.segments) }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 14) {
        Text(L10n.text("Step by step")).font(.title3.weight(.semibold))
        rhythm
        HStack {
          Text("0")
          Spacer()
          Text(timeline.usesDistance ? L10n.text("\(timeline.steps.count) steps") : RunRecording.clock(Double(timeline.totalSeconds)))
        }
        .font(.caption2).monospacedDigit().foregroundStyle(HybrdStyle.muted)
        .accessibilityHidden(true)
        Text(timeline.usesDistance ? L10n.text("Planned sequence · one bar per step") : L10n.text("Planned sequence · bar width shows time"))
          .font(.caption).foregroundStyle(HybrdStyle.muted)
      }

      VStack(alignment: .leading, spacing: 0) {
        ForEach(workout.segments.indices, id: \.self) { index in
          if !isPairedRecovery(index) {
            timelineRow(at: index)
          }
        }
      }
    }
  }

  private var rhythm: some View {
    GeometryReader { geometry in
      let total = max(1, timeline.usesDistance ? timeline.steps.count : timeline.totalSeconds)
      let gap: CGFloat = 3
      let width = max(1, geometry.size.width - CGFloat(max(0, timeline.steps.count - 1)) * gap)
      HStack(alignment: .bottom, spacing: gap) {
        ForEach(timeline.steps) { step in
          RoundedRectangle(cornerRadius: 3)
            .fill(SessionPalette.color(SessionBreakdown.tone(for: step.segment.heartRateZone)))
            .frame(width: width * CGFloat(timeline.usesDistance ? 1 : step.seconds) / CGFloat(total),
              height: 16)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
    .frame(height: 16)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.text("Planned running sequence"))
    .accessibilityValue(timeline.steps.map { step in
      step.segment.localizedTitle + ", " + (step.segment.targets?.summary(units: units) ?? step.segment.targetSummary)
    }.joined(separator: ". "))
  }

  private func timelineRow(at index: Int) -> some View {
    let segment = workout.segments[index]
    let recovery = RunTimeline.pairedRecovery(after: index, in: workout.segments)
    let work = segment.phase == .work
    return HStack(alignment: .top, spacing: 16) {
      VStack(spacing: 0) {
        ZStack {
          Circle().fill(SessionPalette.wash(SessionBreakdown.tone(for: segment.heartRateZone))).frame(width: 34, height: 34)
          Image(systemName: work ? "repeat" : segment.phase == .coolDown ? "flag.checkered" : "figure.run")
            .font(.caption.weight(.semibold))
            .foregroundStyle(SessionPalette.ink(SessionBreakdown.tone(for: segment.heartRateZone)))
        }
        Rectangle().fill(HybrdStyle.line).frame(width: 1)
      }.frame(width: 34).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(recovery == nil ? segment.displayTitle : L10n.text("Repeat \(segment.repetitions ?? 1) times"))
            .font(.headline)
          Spacer(minLength: 8)
          if work {
            Text(L10n.text("WORK")).font(.caption2.weight(.semibold)).tracking(1)
              .foregroundStyle(HybrdStyle.terraText)
          }
        }
        Text(segment.targets?.summary(units: units) ?? segment.durationTargetSummary).font(.title3.weight(.medium)).monospacedDigit()
        if let zone = segment.heartRateZone { RunZoneBadge(zone: zone) }
        Text(segment.localizedCue).font(.subheadline).foregroundStyle(HybrdStyle.muted)
        if let recovery {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.turn.down.right").font(.subheadline)
              .foregroundStyle(HybrdStyle.muted).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
              Text(L10n.text("\(recovery.durationTargetSummary) recovery")).font(.subheadline.weight(.medium))
              if let zone = recovery.heartRateZone { RunZoneBadge(zone: zone) }
              Text(recovery.cue).font(.subheadline).foregroundStyle(HybrdStyle.muted)
            }
          }.padding(.top, 4)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 6).padding(.bottom, 28)
      .accessibilityElement(children: .combine)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private func isPairedRecovery(_ index: Int) -> Bool {
    index > 0 && RunTimeline.pairedRecovery(after: index - 1, in: workout.segments)?.id == workout.segments[index].id
  }
}
