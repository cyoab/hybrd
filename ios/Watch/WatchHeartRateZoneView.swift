import SwiftUI

struct WatchHeartRateZoneView: View {
  var current: HeartRateZone?
  var target: HeartRateZone?

  var body: some View {
    HStack(spacing: 3) {
      ForEach(HeartRateZone.allCases) { zone in
        VStack(spacing: 2) {
          RoundedRectangle(cornerRadius: 3)
            .fill(WatchRunStyle.zoneColor(zone).opacity(current == zone ? 1 : 0.28))
            .overlay {
              if current == zone { RoundedRectangle(cornerRadius: 3).strokeBorder(.white, lineWidth: 1.5) }
            }
            .overlay {
              if current == zone { Image(systemName: "circle.fill").font(.system(size: 4)).foregroundStyle(.black) }
            }
            .frame(height: 9)
          Text(zone.shortTitle).font(.system(size: 9, weight: target == zone ? .bold : .medium, design: .rounded))
            .foregroundStyle(target == zone ? .white : .white.opacity(0.6))
            .underline(target == zone)
        }.frame(maxWidth: .infinity)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.text("Heart rate zones"))
    .accessibilityValue((current.map { L10n.text("Current ") + $0.title } ?? L10n.text("Current zone unavailable")) + (target.map { L10n.text("; target ") + $0.title } ?? L10n.text("; no target")))
  }
}
