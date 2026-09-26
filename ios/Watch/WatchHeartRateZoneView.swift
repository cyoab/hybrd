import SwiftUI

struct WatchHeartRateZoneView: View {
  var current: HeartRateZone?
  var target: HeartRateZone?
  @ScaledMetric(relativeTo: .caption2) private var labelSize = 10

  var body: some View {
    HStack(spacing: 3) {
      ForEach(HeartRateZone.allCases) { zone in
        let selected = current == zone
        Text(zone.shortTitle)
          .font(.system(size: labelSize, weight: selected ? .heavy : .medium, design: .rounded))
          .foregroundStyle(selected ? .black : .white.opacity(0.65))
          .frame(maxWidth: .infinity).padding(.vertical, 3)
          .background(WatchRunStyle.zoneColor(zone).opacity(selected ? 1 : 0.16), in: RoundedRectangle(cornerRadius: 5))
          .overlay {
            if selected { RoundedRectangle(cornerRadius: 5).strokeBorder(.white, lineWidth: 2) }
          }
          .overlay(alignment: .top) {
            if selected {
              Image(systemName: "arrowtriangle.down.fill").font(.system(size: 6)).foregroundStyle(.white).offset(y: -5)
            }
          }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.text("Heart rate zones"))
    .accessibilityValue((current.map { L10n.text("Current ") + $0.title } ?? L10n.text("Current zone unavailable")) + (target.map { L10n.text("; target ") + $0.title } ?? L10n.text("; no target")))
  }
}
