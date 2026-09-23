import SwiftUI

struct OnboardingEntryView: View {
  @Environment(OnboardingStore.self) private var onboarding
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var inJourney = false
  @State private var showSignIn = false
  @State private var restart = false
  var onExit: () -> Void

  var body: some View {
    NavigationStack {
      Group {
        if inJourney { OnboardingJourneyView(onClose: { inJourney = false }, onFinish: onExit) }
        else { welcome }
      }
      .toolbar(.hidden, for: .navigationBar)
      .tint(HybrdStyle.terraText)
      .animation(reduceMotion ? nil : .smooth, value: inJourney)
      .confirmationDialog(L10n.text("Start a new onboarding preview?"), isPresented: $restart, titleVisibility: .visible) {
        Button(L10n.text("Start over"), role: .destructive) { onboarding.restart(); onboarding.begin(); inJourney = true }
        Button(L10n.text("Cancel"), role: .cancel) {}
      } message: { Text(L10n.text("This clears only the saved onboarding answers. Your training history stays in place.")) }
      .sheet(isPresented: $showSignIn) {
        OnboardingInformationView(title: L10n.text("Sign in"), symbol: "person.crop.circle",
          message: L10n.text("Account sign-in isn’t connected in this preview. You can test creating your plan or return to the existing app."))
      }
    }
  }

  private var welcome: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack { HybrdWordmark(); Spacer(); previewBadge }
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
        if let message = onboarding.storageMessage { Text(message).font(.caption).foregroundStyle(HybrdStyle.terraText) }
      }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
    }
    .background { OnboardingBackdrop() }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 14) {
        Button(onboarding.started ? L10n.text("Continue setup") : L10n.text("Create account")) {
          onboarding.begin(); inJourney = true
        }.buttonStyle(HybrdPrimaryButtonStyle())
        Button(L10n.text("Already have an account? Sign in")) { showSignIn = true }
          .font(.subheadline.weight(.medium)).foregroundStyle(HybrdStyle.ink)
        HStack {
          if onboarding.started || onboarding.storageMessage != nil { Button(L10n.text("Start over")) { restart = true } }
          Spacer()
          Button(L10n.text("Explore the app"), action: onExit)
        }.font(.caption).foregroundStyle(HybrdStyle.muted)
        Text(L10n.text("Preview only · No account or payment required"))
          .font(.caption2).foregroundStyle(HybrdStyle.muted).multilineTextAlignment(.center)
      }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background(HybrdStyle.background)
    }
  }
  private var previewBadge: some View {
    Text(L10n.text("PREVIEW")).font(.caption2.weight(.semibold)).tracking(1)
      .padding(.horizontal, 10).padding(.vertical, 6)
      .background(HybrdStyle.surface.opacity(0.8), in: Capsule()).foregroundStyle(HybrdStyle.muted)
  }
}
