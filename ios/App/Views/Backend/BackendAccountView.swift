import SwiftUI

struct BackendAccountView: View {
  @Environment(TrainingStore.self) private var training
  @Environment(BackendAppController.self) private var backend
  @Environment(\.dismiss) private var dismiss
  @State private var discard = false
  @State private var localSignOut = false
  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.text("Account")) {
          Text(backend.session.credential?.user.email ?? backend.connectedEmail ?? "")
          Text(backend.session.environment?.origin.absoluteString ?? "").font(.caption).foregroundStyle(.secondary)
          LabeledContent(L10n.text("API version"), value: backend.session.environment?.apiVersion ?? "")
        }
        Section {
          LabeledContent(L10n.text("Pending changes"), value: backend.pendingCount.formatted())
          if let date = backend.lastSynced { LabeledContent(L10n.text("Last synced"), value: date.formatted(date: .abbreviated, time: .shortened)) }
          if let error = backend.error { Text(error).font(.footnote).foregroundStyle(HybrdStyle.terraText) }
          if !backend.session.authenticated {
            Button(L10n.text("Sign in")) { dismiss(); backend.showAuthentication = true }
          }
          Button(L10n.text("Sync now")) { Task { await backend.refresh() } }.disabled(backend.busy)
          ForEach(backend.conflicts, id: \.mutationId) { result in
            VStack(alignment: .leading) { Text(result.status.rawValue.capitalized).font(.headline); Text(result.error?.code ?? "").font(.caption).textSelection(.enabled) }
          }
          if !backend.conflicts.isEmpty { Button(L10n.text("Use server data"), role: .destructive) { discard = true } }
          if backend.remote?.hasPendingRequest == true || backend.onboardingConflict {
            Button(L10n.text("Retry onboarding save")) { Task { await backend.retryOnboarding() } }
            NavigationLink(L10n.text("Review server answers")) { BackendDraftReviewView() }
          }
        } header: { Text(L10n.text("Sync")) } footer: { Text(L10n.text("Pending changes are kept on this device for this account. A sync conflict needs your review.")) }
        if backend.session.authenticated && (!training.legacyArchives.isEmpty || training.legacyArchiveError != nil) {
          Section {
            NavigationLink(L10n.text("Local training archive")) { LegacyTrainingArchiveView() }
          }
        }
        Section {
          Button(L10n.text("Sign out"), role: .destructive) { Task { await backend.signOut() } }.disabled(backend.busy)
          Button(L10n.text("Sign out on this device"), role: .destructive) { localSignOut = true }.disabled(backend.busy)
        } footer: { Text(L10n.text("Local sign-out removes this device’s credentials. If you’re offline, it does not revoke the server session.")) }
      }
      .navigationTitle(L10n.text("Account & sync"))
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
      .confirmationDialog(L10n.text("Discard pending changes and use the server copy?"), isPresented: $discard, titleVisibility: .visible) {
        Button(L10n.text("Use server data"), role: .destructive) { Task { await backend.useServerTraining() } }
      }
      .confirmationDialog(L10n.text("Sign out on this device?"), isPresented: $localSignOut, titleVisibility: .visible) {
        Button(L10n.text("Sign out"), role: .destructive) { Task { await backend.signOut(localOnly: true) } }
      }
    }
  }
}
