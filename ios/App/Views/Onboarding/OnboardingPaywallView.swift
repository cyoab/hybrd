import SwiftUI

struct OnboardingPaywallView: View {
  @Environment(OnboardingStore.self) private var onboarding
  @State private var information: Information?
  private enum Information: String, Identifiable { case restore, terms, privacy; var id: String { rawValue } }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      OnboardingHero(compact: true, height: 95)
      VStack(alignment: .leading, spacing: 10) {
        Eyebrow(text: L10n.text("hybrd membership"))
        Text(OnboardingStep.paywall.title).font(.system(.title, design: .rounded, weight: .bold)).tracking(-1).fixedSize(horizontal: false, vertical: true)
        Text(L10n.text("For \(onboarding.draft.displayName), and the athlete you’re becoming."))
          .font(.subheadline).foregroundStyle(HybrdStyle.muted)
      }
      VStack(alignment: .leading, spacing: 10) {
        benefit("figure.run", title: L10n.text("Running with direction"), detail: L10n.text("Structured sessions and Watch guidance."), tone: .terra)
        benefit("dumbbell", title: L10n.text("Strength that belongs"), detail: L10n.text("Your goals, equipment, and focus areas."), tone: .violet)
        benefit("chart.xyaxis.line", title: L10n.text("See the work add up"), detail: L10n.text("One place for your training and progress."), tone: .mint)
      }
      ForEach(OnboardingMembership.allCases) { plan in
        Toggle(isOn: Binding(get: { onboarding.draft.membership == plan }, set: { if $0 { onboarding.draft.membership = plan } })) {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: onboarding.draft.membership == plan ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(onboarding.draft.membership == plan ? HybrdStyle.terraText : HybrdStyle.muted)
              .font(.title3).padding(.top, 3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
              ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                  Text(plan.title).font(.headline)
                  Spacer(minLength: 10)
                  Text(plan.price).font(.system(.title2, design: .rounded, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 4) {
                  Text(plan.title).font(.headline)
                  Text(plan.price).font(.system(.title2, design: .rounded, weight: .bold))
                }
              }.frame(maxWidth: .infinity, alignment: .leading)
              Text(plan.billing).font(.caption.weight(.semibold))
              Text(plan.equivalent).font(.caption).foregroundStyle(HybrdStyle.muted)
              if plan == .annual {
                Text(L10n.text("Save \(OnboardingMembership.annualSavingsPercent)%"))
                  .font(.caption.weight(.bold)).foregroundStyle(SessionPalette.ink(.mint))
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.padding(16).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(HybrdStyle.ink)
            .background(onboarding.draft.membership == plan ? HybrdStyle.terraWash : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(onboarding.draft.membership == plan ? HybrdStyle.terra : HybrdStyle.line, lineWidth: onboarding.draft.membership == plan ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }.toggleStyle(.button).buttonStyle(.plain)
      }
      Text(L10n.text("Subscription preview · Prices in USD. The selected plan would renew automatically until canceled. No free trial is included."))
        .font(.caption).foregroundStyle(HybrdStyle.muted)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 20) { links }.fixedSize()
        VStack(alignment: .leading, spacing: 16) { links }
      }.font(.caption).foregroundStyle(HybrdStyle.muted).padding(.vertical, 6)
    }.frame(maxWidth: .infinity, alignment: .leading)
    .sheet(item: $information) { item in
      switch item {
      case .restore:
        OnboardingInformationView(title: L10n.text("Restore purchases"), symbol: "arrow.clockwise",
          message: L10n.text("Purchases aren’t connected in this preview, so there’s nothing to restore. Real subscriptions will be verified through the App Store."))
      case .terms:
        OnboardingInformationView(title: L10n.text("Terms · Preview"), symbol: "doc.text",
          message: L10n.text("This is a subscription design preview. No purchase or subscription agreement is created. Final terms of use will be linked before payments are enabled."))
      case .privacy:
        OnboardingInformationView(title: L10n.text("Your preview data"), symbol: "hand.raised",
          message: L10n.text("Onboarding answers stay on this device in a separate preview draft. Nothing is sent to a server, Apple Health, or Strava. Start over from the welcome screen to clear these answers. Your existing training data is separate."))
      }
    }
  }
  @ViewBuilder private var links: some View {
    Button(L10n.text("Restore purchases")) { information = .restore }
    Button(L10n.text("Terms")) { information = .terms }
    Button(L10n.text("Privacy")) { information = .privacy }
  }
  private func benefit(_ symbol: String, title: String, detail: String, tone: SessionBreakdown.Tone) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol).font(.subheadline).foregroundStyle(SessionPalette.ink(tone))
        .frame(width: 32, height: 32).background(SessionPalette.wash(tone), in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(HybrdStyle.muted)
      }
    }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
  }
}
