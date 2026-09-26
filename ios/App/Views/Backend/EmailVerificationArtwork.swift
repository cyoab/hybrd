import SwiftUI

struct EmailVerificationArtwork: View {
  var body: some View {
    ZStack {
      Capsule().fill(SessionPalette.wash(.mint))
        .frame(width: 210, height: 80).rotationEffect(.degrees(-12))
      Circle().fill(SessionPalette.violet.opacity(0.2))
        .frame(width: 72, height: 72).offset(x: 64, y: -9)
      RoundedRectangle(cornerRadius: 24)
        .fill(HybrdStyle.surface).frame(width: 104, height: 84)
        .overlay {
          Image(systemName: "envelope").font(.system(size: 46, weight: .light))
            .foregroundStyle(SessionPalette.ink(.mint))
        }
        .rotationEffect(.degrees(-8))
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 30)).foregroundStyle(SessionPalette.ink(.mint))
        .background(HybrdStyle.surface, in: Circle()).offset(x: 49, y: 31)
      Circle().fill(HybrdStyle.terra).frame(width: 9, height: 9).offset(x: -83, y: 30)
    }
    .frame(maxWidth: .infinity).accessibilityHidden(true).allowsHitTesting(false)
  }
}
