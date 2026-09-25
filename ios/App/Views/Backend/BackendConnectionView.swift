import SwiftUI

struct BackendConnectionView: View {
  @Environment(BackendAppController.self) private var backend
  @Environment(RunRecorder.self) private var recorder
  @Environment(\.dismiss) private var dismiss
  @State private var origin = ""
  @State private var version = "v1"
  @State private var authPath = "/api/auth"
  @State private var message: String?
  @State private var checking = false
  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.text("Backend connection")) {
          TextField(L10n.text("Server address"), text: $origin, prompt: Text(verbatim: "https://api.example.com"))
            .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
          TextField(L10n.text("API version"), text: $version).textInputAutocapitalization(.never).autocorrectionDisabled()
          TextField(L10n.text("Authentication path"), text: $authPath).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        Section {
          Text(L10n.text("The server address is the domain only. Training requests use the API version; email sign-in uses the authentication path."))
          Text(L10n.text("Changing the version changes request paths, not the data contract. The server must support this app’s schema."))
          #if DEBUG
          Button(L10n.text("Use local Docker backend")) { origin = "http://localhost:3000"; version = "v1"; authPath = "/api/auth" }
          Text(L10n.text("Localhost works in the simulator. For an iPhone, use a reachable HTTPS development server."))
          #endif
        }.font(.footnote).foregroundStyle(.secondary)
        Section {
          Button(L10n.text("Save and check connection")) { Task { await check() } }.disabled(checking || backend.session.credential != nil || recorder.recording != nil)
          if checking { ProgressView(L10n.text("Checking connection…")) }
          if let message { Text(message).font(.footnote) }
          if backend.session.credential != nil { Text(L10n.text("Sign out before changing servers. Pending work stays with its original account.")) }
        }
      }
      .navigationTitle(L10n.text("Connection settings"))
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
      .onAppear { origin = backend.session.environment?.origin.absoluteString ?? ""; version = backend.session.environment?.apiVersion ?? "v1"; authPath = backend.session.environment?.authPath ?? "/api/auth" }
    }
  }
  private func check() async {
    checking = true; defer { checking = false }
    do {
      try backend.session.configure(BackendEnvironment(origin: origin, apiVersion: version, authPath: authPath))
      try await backend.session.checkServer()
      message = backend.session.methods?.emailOtp == true ? L10n.text("Connected. Email sign-in is available.") : L10n.text("Connected. Email sign-in is not enabled on this server yet.")
    } catch { message = BackendErrorMessage.text(error) }
  }
}
