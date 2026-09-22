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
        Text("Fill in your age, height, and weight from the health details you choose to share.")
          .font(.subheadline).foregroundStyle(.secondary)
        if let date = editor.details.lastHealthImport {
          LabeledContent("Last import", value: date.formatted(date: .abbreviated, time: .omitted))
        }
        Button {
          importing = true
          Task {
            defer { importing = false }
            do {
              let result = try await reader.requestImport()
              if result.isEmpty {
                message = "No profile measurements were available. Data may be missing or not shared. You can keep entering everything manually."
              } else { imported = result }
            } catch { message = error.localizedDescription }
          }
        } label: {
          if importing { Label("Reading Health…", systemImage: "hourglass") }
          else { Label("Import from Apple Health", systemImage: "arrow.down.doc") }
        }
        .disabled(importing || !HealthProfileReader.isAvailable)
        if !HealthProfileReader.isAvailable { Text("Unavailable on this device.").font(.caption).foregroundStyle(.secondary) }
      } footer: {
        Text("Read-only access. You’ll review each value before applying it. Manage sharing in Apple Health. Your imported details stay on this iPhone.")
      }

      Section {
        LabeledContent("Strava", value: "Coming soon")
        Text("Profile and running-history import will be available when the Strava connection is ready. You can add your PRs manually today.")
          .font(.subheadline).foregroundStyle(.secondary)
      }

      Section {
        Label("Apple Watch", systemImage: "applewatch").font(.headline)
        Text(store.companion.connectionMessage).font(.subheadline).foregroundStyle(.secondary)
        Button("Send plan to Watch", systemImage: "arrow.triangle.2.circlepath") { store.shareWithWatch() }
      } footer: { Text("Your Watch companion displays upcoming prescriptions.") }

      Section {
        LabeledContent("Profile storage", value: "On this iPhone")
        LabeledContent("Cloud sync", value: "Not connected")
      }
    }
    .navigationTitle("Health & connections").navigationBarTitleDisplayMode(.inline)
    .sheet(item: $imported) { values in HealthImportReviewView(editor: editor, values: values) }
    .alert("Apple Health", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
      Button("OK") { message = nil }
    } message: { Text(message ?? "") }
  }
}
