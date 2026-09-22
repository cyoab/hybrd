import SwiftUI

/// A small overview of the prescribed sequence. Width is time; height is the HR zone.
struct RunRhythmView: View {
  var segments: [RunSegment]
  var type: RunWorkoutType

  var body: some View {
    Canvas { context, size in
      let timeline = RunTimeline(segments: segments)
      let total = max(1, timeline.totalSeconds)
      let gap: CGFloat = 2
      let width = max(0, size.width - CGFloat(max(0, timeline.steps.count - 1)) * gap)
      var x: CGFloat = 0
      for step in timeline.steps {
        let segmentWidth = width * CGFloat(step.seconds) / CGFloat(total)
        let height = size.height * CGFloat(step.segment.heartRateZone?.rawValue ?? 1) / 5
        let rect = CGRect(x: x, y: size.height - height, width: segmentWidth, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: 3),
          with: .color(RunPalette.ink(type).opacity(step.segment.phase == .recovery ? 0.28 : 0.72)))
        x += segmentWidth + gap
      }
    }
    .frame(height: 32)
    .accessibilityHidden(true)
  }
}
