import SwiftUI

/// Prescribed seconds determine width; zone intensity determines height.
struct WatchRunSequenceView: View {
  var steps: [RunTimeline.Step]
  var currentID: Int? = nil

  var body: some View {
    Canvas { context, size in
      let visible = steps.filter { $0.seconds > 0 }
      let total = Double(max(1, visible.reduce(0) { $0 + $1.seconds }))
      var x: CGFloat = 0
      for step in visible {
        let width = size.width * Double(step.seconds) / total
        let level = Double(step.segment.heartRateZone?.rawValue ?? 1)
        let height = size.height * (0.24 + level * 0.15)
        let rect = CGRect(x: x, y: size.height - height, width: max(0.5, width - min(2, width * 0.2)), height: height)
        let color = step.segment.heartRateZone.map(WatchRunStyle.zoneColor) ?? .gray
        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(currentID.map { step.id < $0 ? 0.3 : 0.9 } ?? 0.9)))
        if step.id == currentID { context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(.white), lineWidth: 1.5) }
        x += width
      }
    }
    .accessibilityHidden(true)
  }
}
