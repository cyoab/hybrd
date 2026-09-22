import SwiftUI

struct RunPrescriptionView: View {
  var workout: TrainingWorkout
  private var timeline: RunTimeline { RunTimeline(segments: workout.segments) }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 14) {
        Text("Session rhythm").font(.title3.weight(.semibold))
        rhythm
        HStack {
          Text("0")
          Spacer()
          Text("\(timeline.totalSeconds / 60) min")
        }
        .font(.caption2).monospacedDigit().foregroundStyle(HybrdStyle.muted)
        .accessibilityHidden(true)
        Text("Planned sequence · bar width shows time")
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
      let total = max(1, timeline.totalSeconds)
      let gap: CGFloat = 3
      let width = max(1, geometry.size.width - CGFloat(max(0, timeline.steps.count - 1)) * gap)
      HStack(alignment: .bottom, spacing: gap) {
        ForEach(timeline.steps) { step in
          RoundedRectangle(cornerRadius: 4)
            .fill(barColor(step.segment.phase))
            .frame(width: width * CGFloat(step.seconds) / CGFloat(total),
              height: step.segment.phase == .work ? 76 : step.segment.phase == .recovery ? 24 : 42)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
    .frame(height: 80)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Planned running sequence")
    .accessibilityValue(timeline.steps.map { step in
      step.segment.title + ", " + step.segment.targetSummary
    }.joined(separator: ". "))
  }

  private func timelineRow(at index: Int) -> some View {
    let segment = workout.segments[index]
    let recovery = RunTimeline.pairedRecovery(after: index, in: workout.segments)
    let work = segment.phase == .work
    return HStack(alignment: .top, spacing: 16) {
      VStack(spacing: 0) {
        ZStack {
          Circle().fill(work ? HybrdStyle.terraWash : HybrdStyle.field).frame(width: 34, height: 34)
          Image(systemName: work ? "repeat" : segment.phase == .coolDown ? "flag.checkered" : "figure.run")
            .font(.caption.weight(.semibold))
            .foregroundStyle(work ? HybrdStyle.terraText : HybrdStyle.muted)
        }
        Rectangle().fill(HybrdStyle.line).frame(width: 1)
      }.frame(width: 34).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(recovery == nil ? segment.displayTitle : "Repeat \(segment.repetitions ?? 1) times")
            .font(.headline)
          Spacer(minLength: 8)
          if work {
            Text("WORK").font(.caption2.weight(.semibold)).tracking(1)
              .foregroundStyle(HybrdStyle.terraText)
          }
        }
        Text(segment.targetSummary).font(.title3.weight(.medium)).monospacedDigit()
        Text(segment.cue).font(.subheadline).foregroundStyle(HybrdStyle.muted)
        if let recovery {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.turn.down.right").font(.subheadline)
              .foregroundStyle(HybrdStyle.muted).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
              Text(recovery.targetSummary + " recovery").font(.subheadline.weight(.medium))
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

  private func barColor(_ phase: RunSegmentPhase?) -> Color {
    switch phase {
    case .work: HybrdStyle.terra
    case .recovery: HybrdStyle.muted.opacity(0.55)
    default: HybrdStyle.stone
    }
  }

  private func isPairedRecovery(_ index: Int) -> Bool {
    index > 0 && RunTimeline.pairedRecovery(after: index - 1, in: workout.segments)?.id == workout.segments[index].id
  }
}
