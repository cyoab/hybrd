import SwiftUI

/// A four-second visual story, separate from real account/plan creation.
struct OnboardingPreparationView: View {
  var draft: OnboardingDraft
  var onCancel: () -> Void
  var onComplete: () -> Void
  var connected = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var phase = OnboardingPreparationPhase.running
  @State private var appeared = false

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 26) {
          VStack(spacing: 12) {
            Text(connected ? L10n.text("Preparing your training setup") : L10n.text("Building your hybrid plan"))
              .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-0.8)
            Text(L10n.text("Running and strength, made for \(draft.displayName)."))
              .font(.subheadline).foregroundStyle(HybrdStyle.muted)
          }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          OnboardingPlanArtwork(phase: phase, appeared: appeared, availableDays: draft.availableDays)
            .frame(height: typeSize.isAccessibilitySize ? 220 : min(300, max(210, geometry.size.height * 0.45)))
          VStack(spacing: 22) {
            ZStack {
              ForEach(OnboardingPreparationPhase.allCases) { beat in
                VStack(spacing: 8) {
                  Text(beat.title).font(.headline)
                  Text(beat.detail(for: draft)).font(.subheadline).foregroundStyle(HybrdStyle.muted)
                }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                  .opacity(phase == beat ? 1 : 0)
                  .offset(y: reduceMotion || phase == beat ? 0 : phase.rawValue > beat.rawValue ? -8 : 8)
                  .accessibilityHidden(phase != beat)
              }
            }.animation(reduceMotion ? nil : .smooth(duration: 0.28), value: phase)
            ProgressView(value: appeared ? phase.progress : 0)
              .tint(isTogether ? SessionPalette.mint : HybrdStyle.terra)
              .frame(maxWidth: 170)
              .animation(reduceMotion ? nil : .smooth(duration: 0.85), value: phase)
              .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: appeared)
              .accessibilityLabel(connected ? L10n.text("Preparing your training setup") : L10n.text("Preparing your plan preview"))
            if connected && isTogether { ProgressView(L10n.text("Saving your setup…")) }
          }
        }.padding(.horizontal, 24).padding(.vertical, 22)
          .frame(maxWidth: 560).frame(maxWidth: .infinity)
          .frame(minHeight: geometry.size.height)
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) { navigation }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Text(connected ? L10n.text("We’ll continue once your setup is saved to your account.") : L10n.text("Preview animation · No account or plan is created yet."))
        .font(.caption).foregroundStyle(HybrdStyle.muted).multilineTextAlignment(.center)
        .padding(18).frame(maxWidth: .infinity).background(HybrdStyle.background)
    }
    .background { OnboardingBackdrop(tone: .terra) }
    .sensoryFeedback(.success, trigger: isTogether && !connected)
    .task {
      let clock = ContinuousClock()
      let started = clock.now
      appeared = true
      do {
        for next in OnboardingPreparationPhase.allCases.dropFirst() {
          try await clock.sleep(until: started.advanced(by: .seconds(next.rawValue)))
          try Task.checkCancellation()
          phase = next
        }
        // Leave a full beat for the assembled week before showing membership.
        try await clock.sleep(until: started.advanced(by: .seconds(4)))
        try Task.checkCancellation()
        onComplete()
      } catch {
        // Leaving this screen cancels the story and any later navigation.
      }
    }
  }

  private var isTogether: Bool { phase == .together }
  private var navigation: some View {
    HStack {
      Button(L10n.text("Back"), systemImage: "chevron.left", action: onCancel)
        .disabled(connected).labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 44, height: 44).contentShape(Rectangle())
      Spacer()
      Text(L10n.text("Your next chapter")).font(.caption.weight(.semibold))
      Spacer()
      Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
    }.foregroundStyle(HybrdStyle.ink).padding(.horizontal, 20).padding(.bottom, 8)
  }
}
