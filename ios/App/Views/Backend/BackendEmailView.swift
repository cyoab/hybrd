import SwiftUI

struct BackendEmailView: View {
  @Environment(BackendAppController.self) private var backend
  @Environment(RunRecorder.self) private var recorder
  @Environment(TrainingStore.self) private var training
  @Environment(\.dismiss) private var dismiss
  @State private var email = ""
  @State private var code = ""
  @State private var settings = false
  @State private var discovering = false
  @State private var message: String?
  @FocusState private var focused: Field?
  private enum Field { case email, code }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          HybrdWordmark().padding(.vertical, 12)
          Text(backend.session.codeSent ? L10n.text("Check your inbox") : L10n.text("Your training starts here"))
            .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
          Text(backend.session.codeSent ? L10n.text("Enter the six-digit code sent to your email. Only the newest code works.") : L10n.text("Use your email to create an account or sign back in. No password needed."))
            .foregroundStyle(.secondary)
        }.listRowBackground(Color.clear)
        Section {
          if backend.session.codeSent {
            Text(backend.session.email).textSelection(.enabled)
            TextField(L10n.text("Email code"), text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad).focused($focused, equals: .code)
              .onChange(of: code) { _, value in code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
            Button(L10n.text("Verify and continue")) { Task { await verify() } }
              .disabled(code.count != 6 || working || !backend.canAuthenticateDuringRun)
            Button(L10n.text("Use a different email")) { backend.session.editEmail(); code = ""; message = nil; focused = .email }.disabled(working || backend.lockedRecordingEmail != nil)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
              let remaining = max(0, Int(ceil(backend.session.resendAt.timeIntervalSince(timeline.date))))
              Button(remaining > 0 ? L10n.text("Resend code") + " (\(remaining)s)" : L10n.text("Resend code")) {
                Task { await send(backend.session.email) }
              }.disabled(remaining > 0 || working)
            }
          } else {
            TextField(L10n.text("Email address"), text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
              .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .email).disabled(backend.lockedRecordingEmail != nil)
            Button(L10n.text("Continue with email")) { Task { await send(email) } }
              .disabled(backend.session.methods?.emailOtp != true || working || email.isEmpty)
            Button(L10n.text("I already have a code")) {
              do { try backend.session.resumeCode(for: email); message = nil; focused = .code } catch { message = BackendErrorMessage.text(error) }
            }.disabled(working || email.isEmpty)
          }
          if recorder.recording != nil && !backend.canAuthenticateDuringRun { Text(L10n.text("Finish your active workout before switching accounts.")) }
          if working { ProgressView(L10n.text("Connecting…")) }
          if let message { Text(message).font(.footnote).foregroundStyle(HybrdStyle.terraText) }
          if backend.session.methods?.emailOtp == false { Text(L10n.text("Email sign-in is not enabled on this server yet.")) }
        }
        Section {
          Button(L10n.text("Connection settings")) { settings = true }
          Button(L10n.text("Check connection again")) { Task { await discover() } }.disabled(working)
          if let environment = backend.session.environment { Text(environment.origin.absoluteString + " · " + environment.apiVersion).font(.caption).foregroundStyle(.secondary) }
        }
      }
      .navigationTitle(L10n.text("Sign in"))
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } } }
      .scrollDismissesKeyboard(.interactively)
      .sheet(isPresented: $settings, onDismiss: { Task { await discover() } }) { BackendConnectionView() }
      .task { if let locked = backend.lockedRecordingEmail { email = locked }; await discover() }
      .tint(HybrdStyle.terraText)
    }
  }
  private var working: Bool { discovering || backend.session.isWorking || backend.busy }
  private func discover() async {
    discovering = true; defer { discovering = false }
    do { try await backend.session.discover(); message = nil }
    catch { message = BackendErrorMessage.text(error) }
  }
  private func send(_ address: String) async {
    do { try await backend.session.sendCode(to: address); code = ""; message = nil; focused = .code }
    catch { message = BackendErrorMessage.text(error) }
  }
  private func verify() async {
    do { try await backend.verifyEmail(code, training: training); code = ""; focused = nil; dismiss() }
    catch { message = BackendErrorMessage.text(error) }
  }
}
