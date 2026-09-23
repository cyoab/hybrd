import SwiftUI

struct ProfileConnectionsView: View {
  @Bindable var editor: AthleteProfileEditor
  @Environment(TrainingStore.self) private var store
  @State private var importing = false
  @State private var imported: HealthProfileImport?
  @State private var message: String?
  @State private var reader = HealthProfileReader()

  var body: some View {
    Form {
      Section {
        Label("Apple Health", systemImage: "heart.fill").font(.headline).foregroundStyle(HybrdStyle.terraText)
        Text(L10n.text("Fill in your age, height, and weight from the health details you choose to share."))
          .font(.subheadline).foregroundStyle(.secondary)
        if let date = editor.details.lastHealthImport {
          LabeledContent(L10n.text("Last import"), value: date.formatted(date: .abbreviated, time: .omitted))
        }
        Button {
          importing = true
          Task {
            defer { importing = false }
            do {
              let result = try await reader.requestImport()
              if result.isEmpty {
                message = L10n.text("No profile measurements were available. Data may be missing or not shared. You can keep entering everything manually.")
              } else { imported = result }
            } catch { message = error.localizedDescription }
          }
        } label: {
          if importing { Label(L10n.text("Reading Health…"), systemImage: "hourglass") }
          else { Label(L10n.text("Import from Apple Health"), systemImage: "arrow.down.doc") }
        }
        .disabled(importing || !HealthProfileReader.isAvailable)
        if !HealthProfileReader.isAvailable { Text(L10n.text("Unavailable on this device.")).font(.caption).foregroundStyle(.secondary) }
      } footer: {
        Text(L10n.text("Read-only access. You’ll review each value before applying it. Manage sharing in Apple Health. Your imported details stay on this iPhone."))
      }

      Section {
        LabeledContent("Strava", value: L10n.text("Coming soon"))
        Text(L10n.text("Profile and running-history import will be available when the Strava connection is ready. You can add your PRs manually today."))
          .font(.subheadline).foregroundStyle(.secondary)
      }

      Section {
        Label("Apple Watch", systemImage: "applewatch").font(.headline)
        Text(store.companion.connectionMessage).font(.subheadline).foregroundStyle(.secondary)
        Button(L10n.text("Send plan to Watch"), systemImage: "arrow.triangle.2.circlepath") { store.shareWithWatch() }
      } footer: { Text(L10n.text("Your Watch companion displays upcoming prescriptions.")) }

      Section {
        LabeledContent(L10n.text("Profile storage"), value: L10n.text("On this iPhone"))
        LabeledContent(L10n.text("Cloud sync"), value: L10n.text("Not connected"))
      }
    }
    .navigationTitle(L10n.text("Health & connections")).navigationBarTitleDisplayMode(.inline)
    .sheet(item: $imported) { values in HealthImportReviewView(editor: editor, values: values) }
    .alert("Apple Health", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
      Button(L10n.text("OK")) { message = nil }
    } message: { Text(message ?? "") }
  }
}
