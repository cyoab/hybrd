import SwiftUI

struct RunZoneBadge: View {
  var zone: HeartRateZone
  private var tone: SessionBreakdown.Tone { SessionBreakdown.tone(for: zone) }

  var body: some View {
    Label(zone.title + " · " + zone.name, systemImage: "heart.fill")
      .font(.caption.weight(.semibold))
      .foregroundStyle(SessionPalette.ink(tone))
      .padding(.horizontal, 10).padding(.vertical, 7)
      .background(SessionPalette.wash(tone), in: Capsule())
      .accessibilityLabel("Target heart rate: " + zone.title + ", " + zone.name)
  }
}
