import SwiftUI

struct RunZoneBadge: View {
  @Environment(TrainingStore.self) private var store
  var zone: HeartRateZone
  var personalZones: PersonalHeartRateZones?
  private var tone: SessionBreakdown.Tone { SessionBreakdown.tone(for: zone) }
  private var ranges: PersonalHeartRateZones? { personalZones ?? store.profile.athlete?.heartRateZones }
  private var title: String {
    zone.title + " · " + (ranges?.label(for: zone) ?? zone.name)
  }

  var body: some View {
    Label(title, systemImage: "heart.fill")
      .font(.caption.weight(.semibold))
      .foregroundStyle(SessionPalette.ink(tone))
      .padding(.horizontal, 10).padding(.vertical, 7)
      .background(SessionPalette.wash(tone), in: RoundedRectangle(cornerRadius: 14))
      .accessibilityLabel(L10n.text("Target heart rate: ") + title)
  }
}
