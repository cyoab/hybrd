import SwiftUI

struct OnboardingJourneyView: View {
  @Environment(OnboardingStore.self) private var onboarding
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var attempted = false
  var onClose: () -> Void
  var onFinish: () -> Void

  var body: some View {
    Group {
      if onboarding.completed { completion }
      else {
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              Color.clear.frame(height: 0).id("question")
              if onboarding.step != .paywall {
                VStack(alignment: .leading, spacing: 12) {
                  Text(onboarding.step.title).font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-0.8)
                  Text(onboarding.step.detail).font(.body).foregroundStyle(HybrdStyle.muted)
                }.fixedSize(horizontal: false, vertical: true)
              }
              if onboarding.step == .paywall { OnboardingPaywallView() }
              else if onboarding.step == .summary { OnboardingSummaryView() }
              else { OnboardingQuestionView() }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
            .frame(maxWidth: 600).frame(maxWidth: .infinity, alignment: .leading)
          }
          .scrollDismissesKeyboard(.interactively)
          .onChange(of: onboarding.step) { _, _ in attempted = false; proxy.scrollTo("question", anchor: .top) }
        }
        .safeAreaInset(edge: .top, spacing: 0) { navigation }
        .safeAreaInset(edge: .bottom, spacing: 0) { continueButton }
        .background { OnboardingBackdrop(tone: tone) }
        .animation(reduceMotion ? nil : .smooth, value: onboarding.step)
        .sensoryFeedback(.selection, trigger: onboarding.step)
      }
    }
    .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(L10n.text("Done")) { hideKeyboard() } } }
  }
  private var tone: SessionBreakdown.Tone {
    switch onboarding.step {
    case .strength, .equipment, .focus: .violet
    case .rhythm, .readiness, .connections, .summary: .mint
    default: .terra
    }
  }
  private var navigation: some View {
    VStack(spacing: 12) {
      HStack {
        Button(L10n.text("Back"), systemImage: "chevron.left") {
          hideKeyboard()
          if onboarding.step == .identity && !onboarding.reviewing { onClose() } else { onboarding.back() }
        }.labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
        Spacer()
        VStack(spacing: 3) {
          Text(onboarding.step.chapter).font(.caption.weight(.semibold))
          Text(L10n.text("\(onboarding.step.rawValue + 1) of \(OnboardingStep.allCases.count)"))
            .font(.caption2).foregroundStyle(HybrdStyle.muted)
        }
        Spacer()
        Button(L10n.text("Save and close"), systemImage: "xmark", action: onClose)
          .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
      }.foregroundStyle(HybrdStyle.ink)
      ProgressView(value: Double(onboarding.step.rawValue + 1), total: Double(OnboardingStep.allCases.count))
        .tint(SessionPalette.color(tone)).accessibilityLabel(L10n.text("Onboarding progress"))
    }.padding(.horizontal, 20).padding(.bottom, 14)
      .frame(maxWidth: 600).frame(maxWidth: .infinity).background(HybrdStyle.background.opacity(0.96))
  }
  private var continueButton: some View {
    VStack(spacing: 8) {
      if attempted, let error = onboarding.draft.validation(for: onboarding.step) {
        Text(error).font(.caption).foregroundStyle(HybrdStyle.terraText).frame(maxWidth: .infinity, alignment: .leading)
      }
      if let message = onboarding.storageMessage { Text(message).font(.caption).foregroundStyle(HybrdStyle.terraText) }
      if onboarding.step == .paywall {
        Text(L10n.text("Preview only. You won’t be charged."))
          .font(.caption).foregroundStyle(HybrdStyle.muted)
      }
      Button(buttonTitle) {
        hideKeyboard(); attempted = true
        if onboarding.step == .paywall { _ = onboarding.finishPreview() }
        else { _ = onboarding.advance() }
      }.buttonStyle(HybrdPrimaryButtonStyle())
      if onboarding.step == .body {
        Button(L10n.text("Skip for now")) {
          onboarding.draft.age = ""; onboarding.draft.weight = ""; onboarding.draft.height = ""
          _ = onboarding.advance()
        }.font(.caption).padding(.top, 3)
      }
    }.padding(.horizontal, 24).padding(.vertical, 14).frame(maxWidth: 600).frame(maxWidth: .infinity)
      .background(HybrdStyle.background)
  }
  private var buttonTitle: String {
    if onboarding.reviewing { return L10n.text("Save & review") }
    if onboarding.step == .summary { return L10n.text("See membership options") }
    if onboarding.step == .paywall {
      return onboarding.draft.membership == .annual ? L10n.text("Continue with annual") : L10n.text("Continue with monthly")
    }
    return L10n.text("Continue")
  }
  private var completion: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        OnboardingHero(compact: true)
        Label(L10n.text("Setup preview complete"), systemImage: "checkmark.seal.fill")
          .font(.headline).foregroundStyle(SessionPalette.ink(.mint))
        Text(L10n.text("Your next chapter, \(onboarding.draft.displayName)."))
          .font(.system(.largeTitle, design: .rounded, weight: .bold))
        Text(onboarding.draft.personalMessage).font(.title3).foregroundStyle(HybrdStyle.muted)
        Text(L10n.text("Your answers and membership choice are saved on this device for testing. No account was created and no payment was made."))
          .font(.subheadline).foregroundStyle(HybrdStyle.muted)
        Text(L10n.text("Your existing profile and workouts stay as they are during this preview."))
          .font(.caption).foregroundStyle(HybrdStyle.muted)
        Button(L10n.text("Explore hybrd"), action: onFinish).buttonStyle(HybrdPrimaryButtonStyle())
        Button(L10n.text("Review my answers")) { onboarding.edit(.summary) }.frame(maxWidth: .infinity)
      }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
    }.background { OnboardingBackdrop(tone: .mint) }
  }
  private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}
