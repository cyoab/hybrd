import SwiftUI

struct OnboardingHero: View {
  var compact = false
  var height: CGFloat? = nil
  var body: some View {
    GeometryReader { geometry in
      let width = min(geometry.size.width, geometry.size.height * 1.7, 370)
      ZStack {
        Ellipse().stroke(HybrdStyle.line.opacity(0.8), lineWidth: 1)
          .frame(width: width * 0.92, height: width * 0.34).rotationEffect(.degrees(-22))
        Circle().fill(SessionPalette.wash(.terra)).frame(width: width * 0.54)
          .offset(x: -width * 0.17, y: -10)
        Circle().fill(SessionPalette.wash(.violet)).frame(width: width * 0.43)
          .offset(x: width * 0.24, y: 12)
        Image("SessionShoe").resizable().scaledToFit()
          .frame(width: width * 0.63).rotationEffect(.degrees(-14)).offset(x: -width * 0.16, y: -10)
        Image("SessionDumbbell").resizable().scaledToFit()
          .frame(width: width * 0.43).rotationEffect(.degrees(15)).offset(x: width * 0.23, y: 17)
        Image(systemName: "sparkle").font(.title2).foregroundStyle(HybrdStyle.terra)
          .offset(x: width * 0.30, y: -width * 0.18)
        Circle().fill(SessionPalette.mint).frame(width: 10, height: 10).offset(x: -width * 0.34, y: width * 0.19)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(height: height ?? (compact ? 160 : 215))
    .accessibilityHidden(true).allowsHitTesting(false)
  }
}
