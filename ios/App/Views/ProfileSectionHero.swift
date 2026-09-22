import SwiftUI

struct ProfileSectionHero: View {
  var eyebrow: String
  var title: String
  var subtitle: String
  var artwork: ProfileIllustration.Artwork
  var tone: SessionBreakdown.Tone
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      let layout = typeSize.isAccessibilitySize ?
        AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) :
        AnyLayout(HStackLayout(alignment: .center, spacing: 8))
      layout {
        VStack(alignment: .leading, spacing: 9) {
          Text(eyebrow.uppercased()).font(.caption2.weight(.semibold)).tracking(1.4)
            .foregroundStyle(SessionPalette.ink(tone)).fixedSize(horizontal: false, vertical: true)
          Text(title).font(.system(.title2, design: .rounded, weight: .semibold))
            .foregroundStyle(HybrdStyle.ink).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
        ProfileIllustration(artwork: artwork).frame(width: 112, height: 105)
      }
      Text(subtitle).font(.subheadline).foregroundStyle(HybrdStyle.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
    .background(LinearGradient(colors: [SessionPalette.wash(tone), SessionPalette.wash(.gold).opacity(0.55)],
      startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
  }
}
