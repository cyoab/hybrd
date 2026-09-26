import SwiftUI

struct BackendDraftReviewView: View {
  @Environment(BackendAppController.self) private var backend
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    Form {
      Section(L10n.text("On this device")) {
        if let d = backend.onboarding?.draft {
          LabeledContent(L10n.text("Name"), value: d.displayName)
          LabeledContent(L10n.text("Weekly running distance"), value: d.weeklyMeters.map { d.units.distanceText($0) } ?? "—")
          LabeledContent(L10n.text("Your goals"), value: [d.runningGoal?.displayName, d.strengthGoal?.displayName].compactMap { $0 }.joined(separator: " · "))
        }
      }
      Section(L10n.text("Saved on server")) {
        if let d = backend.remote?.state?.draft {
          LabeledContent(L10n.text("Name"), value: d.details.preferredName ?? "—")
          LabeledContent(L10n.text("Weekly running distance"), value: d.weeklyDistanceM.map { TrainingUnits.metric.distanceText($0) } ?? "—")
          LabeledContent(L10n.text("Your goals"), value: [ConnectedDraftMapping.runGoal(d.runningGoal)?.displayName, d.strengthGoal?.rawValue].compactMap { $0 }.joined(separator: " · "))
        }
      }
      Section {
        Button(L10n.text("Retry onboarding save")) { Task { await backend.retryOnboarding() } }
        Button(L10n.text("Use server data"), role: .destructive) { Task { await backend.useServerOnboarding(); dismiss() } }
      } footer: { Text(L10n.text("Using the server copy replaces the local onboarding answers shown here.")) }
      if let error = backend.error { Text(error).foregroundStyle(HybrdStyle.terraText) }
    }.navigationTitle(L10n.text("Review server answers"))
      .task { await backend.fetchOnboardingForReview() }
  }
}
