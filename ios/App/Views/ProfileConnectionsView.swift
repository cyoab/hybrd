import SwiftUI

struct ProfileConnectionsView: View {
  @Environment(TrainingStore.self) private var store

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Label("Apple Watch", systemImage: "applewatch").font(.headline)
          Text(store.companion.connectionMessage).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
        Button("Send plan to Watch", systemImage: "arrow.triangle.2.circlepath") { store.shareWithWatch() }
      } footer: {
        Text("Your Watch companion displays upcoming prescriptions.")
      }
      Section {
        LabeledContent("Training data", value: "On this iPhone")
        LabeledContent("Cloud AI", value: "Not connected")
      } footer: {
        Text("Cloud sync, HealthKit import, and cloud coaching aren’t enabled in this build.")
      }
    }
    .navigationTitle("Connections")
    .navigationBarTitleDisplayMode(.inline)
  }
}
