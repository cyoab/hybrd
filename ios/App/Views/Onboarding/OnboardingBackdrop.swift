import SwiftUI

struct OnboardingBackdrop: View {
  var tone: SessionBreakdown.Tone = .terra
  var body: some View {
    LinearGradient(stops: [
      .init(color: SessionPalette.wash(tone), location: 0),
      .init(color: HybrdStyle.background, location: 0.65)
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
    .ignoresSafeArea(.container)
  }
}
