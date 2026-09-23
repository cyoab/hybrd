import SwiftUI

/// A four-second presentation, not a signal that remote account or plan creation succeeded.
struct OnboardingPreparationView: View {
  var draft: OnboardingDraft
  var onCancel: () -> Void
  var onComplete: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var phase = 0

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        ZStack {
          Circle().stroke(SessionPalette.wash(.mint), lineWidth: 7)
          Circle().trim(from: 0, to: Double(min(phase, 3)) / 3)
            .stroke(SessionPalette.mint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            .rotationEffect(.degrees(-90))
          OnboardingHero(compact: true, height: 135)
        }.frame(width: 170, height: 170)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(L10n.text("Preparing your plan preview"))
          .accessibilityValue((Double(min(phase, 3)) / 3).formatted(.percent))
        VStack(spacing: 12) {
          Text(L10n.text("Building your hybrid plan"))
            .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-0.8)
          Text(L10n.text("Running and strength, made for \(draft.displayName)."))
            .font(.body).foregroundStyle(HybrdStyle.muted)
        }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        VStack(spacing: 12) {
          stage(1, title: L10n.text("Your goals"), detail: [draft.runningGoal?.displayName, draft.strengthGoal?.displayName].compactMap { $0 }.joined(separator: " · "), symbol: "scope", tone: .terra)
          stage(2, title: L10n.text("Your starting point"), detail: L10n.text("\(draft.runningLevel?.displayName ?? "") running · \(draft.strengthLevel?.displayName ?? "") lifting"), symbol: "figure.run", tone: .violet)
          stage(3, title: L10n.text("Your weekly rhythm"), detail: L10n.text("\(draft.availableDays.count) days per week") + " · " + L10n.text("\(draft.sessionMinutes) min"), symbol: "calendar", tone: .mint)
        }
      }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      HStack {
        Button(L10n.text("Back"), systemImage: "chevron.left", action: onCancel)
          .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 44, height: 44).contentShape(Rectangle())
        Spacer()
        Text(L10n.text("Your next chapter")).font(.caption.weight(.semibold))
        Spacer()
        Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
      }.foregroundStyle(HybrdStyle.ink).padding(.horizontal, 20).padding(.bottom, 8)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Text(L10n.text("Preview animation · No account or plan is created yet."))
        .font(.caption).foregroundStyle(HybrdStyle.muted).multilineTextAlignment(.center)
        .padding(18).frame(maxWidth: .infinity).background(HybrdStyle.background)
    }
    .background { OnboardingBackdrop(tone: .mint) }
    .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: phase)
    .task {
      // Absolute deadlines keep the total at four seconds instead of accumulating animation delays.
      let clock = ContinuousClock()
      let started = clock.now
      do {
        for next in 1...4 {
          try await clock.sleep(until: started.advanced(by: .seconds(next)))
          try Task.checkCancellation()
          phase = next
        }
        onComplete()
      } catch {
        // Going back or dismissing cancels this task; it must never advance navigation later.
      }
    }
  }

  private func stage(_ index: Int, title: String, detail: String, symbol: String, tone: SessionBreakdown.Tone) -> some View {
    HStack(spacing: 14) {
      Image(systemName: phase >= index ? "checkmark" : symbol)
        .font(.headline).foregroundStyle(SessionPalette.ink(tone))
        .frame(width: 42, height: 42).background(SessionPalette.wash(tone), in: RoundedRectangle(cornerRadius: 14))
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace)).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(HybrdStyle.muted)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(14).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
      .accessibilityElement(children: .combine)
      .accessibilityValue(phase >= index ? L10n.text("Done") : "")
  }
}
