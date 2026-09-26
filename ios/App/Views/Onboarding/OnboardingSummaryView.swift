import SwiftUI

struct OnboardingSummaryView: View {
  @Environment(OnboardingStore.self) private var onboarding
  var connected = false
  private var draft: OnboardingDraft { onboarding.draft }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          VStack(alignment: .leading, spacing: 6) {
            Text(draft.displayName).font(.system(.title, design: .rounded, weight: .bold))
            Text(draft.priority?.displayName ?? "").font(.subheadline).foregroundStyle(SessionPalette.ink(.mint))
          }
          Spacer()
          ProfileIllustration(artwork: .experience).frame(width: 105, height: 85)
        }
        Text(draft.personalMessage).font(.body)
      }.padding(22).background(SessionPalette.wash(.mint), in: RoundedRectangle(cornerRadius: 26))
      summaryRow(L10n.text("Your name"), value: draft.displayName, symbol: "person", step: .identity)
      summaryRow(L10n.text("Your balance"), value: draft.priority?.displayName ?? "", symbol: "circle.lefthalf.filled", step: .balance)
      summaryRow(L10n.text("Your goals"), value: [draft.runningGoal?.displayName, draft.strengthGoal?.displayName].compactMap { $0 }.joined(separator: " · "), symbol: "scope", step: .goals)
      if draft.hasRaceDate && draft.runningGoal != .fitness {
        summaryRow(L10n.text("Race date"), value: draft.raceDate.formatted(date: .abbreviated, time: .omitted), symbol: "flag.checkered", step: .goals)
      }
      summaryRow(L10n.text("Running right now"), value: [draft.runningLevel?.displayName, draft.weeklyMeters.map { L10n.text("\(draft.units.distanceText($0)) per week") }].compactMap { $0 }.joined(separator: " · "), symbol: "figure.run", step: .running)
      summaryRow(L10n.text("Lifting right now"), value: (draft.strengthLevel?.displayName ?? "") + " · " + draft.currentLiftDays.formatted() + " " + L10n.text("sessions per week"), symbol: "dumbbell", step: .strength)
      summaryRow(L10n.text("Your weekly rhythm"), value: days + "\n" + L10n.text("\(draft.strengthDays) lifting days · \(draft.sessionMinutes) min per session"), symbol: "calendar", step: .rhythm)
      summaryRow(L10n.text("Your gym"), value: draft.equipment.isEmpty ? L10n.text("Bodyweight setup") : GymEquipment.allCases.filter { draft.equipment.contains($0) }.map(\.title).joined(separator: ", "), symbol: "building.2", step: .equipment)
      summaryRow(L10n.text("Muscle focus"), value: draft.focusMuscles.isEmpty ? L10n.text("Balanced, no priority muscles") : MuscleGroup.allCases.filter { draft.focusMuscles.contains($0) }.map(\.title).joined(separator: ", "), symbol: "figure.strengthtraining.functional", step: .focus)
      summaryRow(L10n.text("Your starting mindset"), value: draft.readiness?.title ?? "", symbol: "leaf", step: .readiness)
      if !draft.context.isEmpty { Text(draft.context).font(.subheadline).foregroundStyle(HybrdStyle.muted).padding(.horizontal, 18) }
      summaryRow(L10n.text("About you"), value: bodySummary, symbol: "person", step: .body)
      if !connected { summaryRow(L10n.text("Connect later"), value: connections, symbol: "link", step: .connections) }
      Text(connected ? L10n.text("Review these answers before saving your athlete setup to your account. You can review a starter plan afterward.") : L10n.text("This is your onboarding summary, not a generated training prescription. We’ll connect plan creation after this flow is tested."))
        .font(.caption).foregroundStyle(HybrdStyle.muted)
    }
  }
  private var days: String {
    (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
      .filter { draft.availableDays.contains($0) }.map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: " · ")
  }
  private var bodySummary: String {
    let parts: [String?] = [draft.ageYears.map { L10n.text("\($0) years") }, draft.weightKilograms.map { draft.units.weightText($0) }, draft.heightSummary]
    let known = parts.compactMap { $0 }
    return known.isEmpty ? L10n.text("Add details later") : known.joined(separator: " · ")
  }
  private var connections: String {
    let choices = [draft.wantsHealth ? L10n.text("Apple Health") : nil, draft.wantsStrava ? L10n.text("Strava") : nil].compactMap { $0 }
    return choices.isEmpty ? L10n.text("Decide later") : choices.joined(separator: " · ")
  }
  private func summaryRow(_ title: String, value: String, symbol: String, step: OnboardingStep) -> some View {
    Button { onboarding.edit(step) } label: {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: symbol).foregroundStyle(HybrdStyle.terraText).frame(width: 23).padding(.top, 3).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          Text(title).font(.subheadline.weight(.semibold))
          Text(value).font(.subheadline).foregroundStyle(HybrdStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "pencil").font(.caption).foregroundStyle(HybrdStyle.muted).accessibilityHidden(true)
      }.padding(18).foregroundStyle(HybrdStyle.ink).frame(maxWidth: .infinity, alignment: .leading)
        .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }.buttonStyle(.plain).accessibilityHint(L10n.text("Edit this answer"))
  }
}
