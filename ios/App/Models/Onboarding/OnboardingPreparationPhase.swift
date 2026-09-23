import Foundation

/// Visual story beats only; none of these indicate backend completion.
enum OnboardingPreparationPhase: Int, CaseIterable, Identifiable {
  case running, strength, rhythm, together
  var id: Int { rawValue }
  var progress: Double { Double(rawValue + 1) / Double(Self.allCases.count) }
  var title: String {
    switch self {
    case .running: L10n.text("Finding your running rhythm")
    case .strength: L10n.text("Making room for strength")
    case .rhythm: L10n.text("Bringing your week together")
    case .together: L10n.text("Two disciplines. One plan.")
    }
  }
  func detail(for draft: OnboardingDraft) -> String {
    switch self {
    case .running: draft.runningGoal?.displayName ?? ""
    case .strength: draft.strengthGoal?.displayName ?? ""
    case .rhythm: L10n.text("\(draft.availableDays.count) days per week") + " · " + L10n.text("\(draft.sessionMinutes) min")
    case .together: L10n.text("Built around you, \(draft.displayName).")
    }
  }
}
