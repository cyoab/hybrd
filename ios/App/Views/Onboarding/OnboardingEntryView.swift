import SwiftUI

struct OnboardingEntryView: View {
  @Environment(BackendAppController.self) private var backend
  var body: some View {
    NavigationStack {
      welcome
        .toolbar(.hidden, for: .navigationBar)
        .tint(HybrdStyle.terraText)
    }
  }

  private var welcome: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack { HybrdWordmark(); Spacer() }
        OnboardingHero()
        VStack(alignment: .leading, spacing: 12) {
          Eyebrow(text: L10n.text("One athlete. Both worlds."))
          Text(L10n.text("Run stronger.\nLift with purpose."))
            .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1)
            .fixedSize(horizontal: false, vertical: true)
          Text(L10n.text("A training rhythm built around your goals, your starting point, and your real life."))
            .font(.body).foregroundStyle(HybrdStyle.muted)
        }
        HStack(spacing: 10) {
          Label(L10n.text("Your goals"), systemImage: "scope")
          Spacer(minLength: 0)
          Label(L10n.text("Your rhythm"), systemImage: "waveform.path")
        }.font(.caption.weight(.semibold)).foregroundStyle(HybrdStyle.terraText)
      }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
    }
    .background { OnboardingBackdrop() }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 14) {
        Button(L10n.text("Create account")) {
          backend.showAuthentication = true
        }.buttonStyle(HybrdPrimaryButtonStyle())
        Button(L10n.text("Already have an account? Sign in")) { backend.showAuthentication = true }
          .font(.subheadline.weight(.medium)).foregroundStyle(HybrdStyle.ink)
      }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background(HybrdStyle.background)
    }
  }
}
