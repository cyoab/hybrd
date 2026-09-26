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
      ScrollView {
        VStack(spacing: 24) {
          introduction
          VStack(alignment: .leading, spacing: 14) {
            if backend.session.codeSent { codeField } else { emailField }
            status
            primaryAction
            if backend.session.codeSent { codeActions } else { resumeAction }
          }
          if !backend.session.codeSent {
            SignInProvidersView().disabled(working || !backend.canAuthenticateDuringRun)
          }
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 28)
        .frame(maxWidth: 480).frame(maxWidth: .infinity)
      }
      .background { OnboardingBackdrop(tone: backend.session.codeSent ? .mint : .terra) }
      .foregroundStyle(HybrdStyle.ink)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Cancel"), systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .principal) { HybrdWordmark() }
        ToolbarItem(placement: .topBarTrailing) {
          Button(L10n.text("Connection settings"), systemImage: "gearshape") { focused = nil; settings = true }
            .labelStyle(.iconOnly).disabled(working)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .sheet(isPresented: $settings, onDismiss: { Task { await discover() } }) { BackendConnectionView() }
      .task {
        email = backend.lockedRecordingEmail ?? backend.session.email
        await discover()
      }
      .tint(HybrdStyle.terraText)
    }
  }

  private var introduction: some View {
    VStack(spacing: 12) {
      if backend.session.codeSent {
        EmailVerificationArtwork().frame(height: 112)
      } else {
        OnboardingHero(height: 128)
      }
      Text(backend.session.codeSent ? L10n.text("Check your inbox") : L10n.text("Stronger starts here."))
        .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-0.8)
        .accessibilityAddTraits(.isHeader)
      if backend.session.codeSent {
        VStack(spacing: 5) {
          Text(L10n.text("We sent a six-digit code to"))
            .foregroundStyle(HybrdStyle.muted)
          Text(backend.session.email).fontWeight(.semibold).textSelection(.enabled)
        }
      } else {
        Text(L10n.text("Sign in or create an account for your running and strength journey."))
          .foregroundStyle(HybrdStyle.muted)
      }
    }
    .font(.subheadline).multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
  }

  private var emailField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.text("Email address")).font(.subheadline.weight(.semibold))
      HStack(spacing: 12) {
        Image(systemName: "envelope").foregroundStyle(HybrdStyle.muted).accessibilityHidden(true)
        TextField(L10n.text("Email address"), text: $email)
          .textContentType(.emailAddress).keyboardType(.emailAddress)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .focused($focused, equals: .email).disabled(backend.lockedRecordingEmail != nil || working)
          .submitLabel(.continue).onSubmit { if canSend { Task { await send(email) } } }
          .accessibilityIdentifier("signIn.email")
      }
      .padding(16).frame(minHeight: 56)
      .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(focused == .email ? HybrdStyle.terraText : HybrdStyle.line, lineWidth: 1))
      Text(L10n.text("No password needed. We’ll email you a sign-in code."))
        .font(.caption).foregroundStyle(HybrdStyle.muted)
    }
  }

  private var codeField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.text("Email code")).font(.subheadline.weight(.semibold))
      TextField(L10n.text("Email code"), text: $code, prompt: Text(verbatim: "000000"))
        .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
        .multilineTextAlignment(.center)
        .textContentType(.oneTimeCode).keyboardType(.numberPad)
        .focused($focused, equals: .code).disabled(working)
        .onChange(of: code) { _, value in code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
        .padding(16).frame(maxWidth: .infinity, minHeight: 72)
        .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(focused == .code ? HybrdStyle.terraText : HybrdStyle.line, lineWidth: 1))
        .accessibilityIdentifier("signIn.code")
      Text(L10n.text("Only the newest code works."))
        .font(.caption).foregroundStyle(HybrdStyle.muted)
    }
  }

  @ViewBuilder private var status: some View {
    if recorder.recording != nil && !backend.canAuthenticateDuringRun {
      Text(L10n.text("Finish your active workout before switching accounts."))
        .font(.footnote).foregroundStyle(HybrdStyle.terraText)
    }
    if let message {
      Label { Text(message).fixedSize(horizontal: false, vertical: true) } icon: {
        Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
      }
      .font(.footnote).foregroundStyle(HybrdStyle.terraText)
      .padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(HybrdStyle.terraWash, in: RoundedRectangle(cornerRadius: 14))
      .accessibilityElement(children: .combine)
    }
    if backend.session.methods?.emailOtp == false {
      Text(L10n.text("Email sign-in is not enabled on this server yet."))
        .font(.footnote).foregroundStyle(HybrdStyle.muted)
    }
    if !discovering && backend.session.methods?.emailOtp != true {
      Button(L10n.text("Check connection again"), systemImage: "arrow.clockwise") {
        Task { await discover() }
      }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(working)
    }
  }

  private var primaryAction: some View {
    Button {
      Task { if backend.session.codeSent { await verify() } else { await send(email) } }
    } label: {
      HStack(spacing: 10) {
        if working { ProgressView().tint(HybrdStyle.primaryButtonText) }
        Text(working ? L10n.text("Connecting…") : (backend.session.codeSent ? L10n.text("Verify and continue") : L10n.text("Continue with email")))
          .multilineTextAlignment(.center).padding(.vertical, 4)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(HybrdPrimaryButtonStyle())
    .disabled(backend.session.codeSent ? !canVerify : !canSend)
    .accessibilityIdentifier("signIn.continue")
  }

  private var resumeAction: some View {
    Button(L10n.text("I already have a code")) {
      do { try backend.session.resumeCode(for: email); message = nil; focused = .code }
      catch { message = BackendErrorMessage.text(error) }
    }
    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
    .disabled(working || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !backend.canAuthenticateDuringRun)
  }

  private var codeActions: some View {
    VStack(spacing: 4) {
      TimelineView(.periodic(from: .now, by: 1)) { timeline in
        let remaining = max(0, Int(ceil(backend.session.resendAt.timeIntervalSince(timeline.date))))
        Button(remaining > 0 ? L10n.text("Resend code in \(remaining) s") : L10n.text("Resend code")) {
          Task { await send(backend.session.email) }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(remaining > 0 || working || !backend.canAuthenticateDuringRun)
      }
      Button(L10n.text("Use a different email")) {
        email = backend.session.email
        backend.session.editEmail(); code = ""; message = nil; focused = .email
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .disabled(working || backend.lockedRecordingEmail != nil)
    }.font(.subheadline.weight(.medium))
  }

  private var working: Bool { discovering || backend.session.isWorking || backend.busy }
  private var canSend: Bool {
    backend.session.methods?.emailOtp == true && !working &&
      !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && backend.canAuthenticateDuringRun
  }
  private var canVerify: Bool { code.count == 6 && !working && backend.canAuthenticateDuringRun }
  private func discover() async {
    discovering = true; defer { discovering = false }
    do { try await backend.session.discover(); message = nil }
    catch { message = BackendErrorMessage.text(error) }
  }
  private func send(_ address: String) async {
    message = nil
    do { try await backend.session.sendCode(to: address); code = ""; focused = .code }
    catch { message = BackendErrorMessage.text(error) }
  }
  private func verify() async {
    message = nil
    do { try await backend.verifyEmail(code, training: training); code = ""; focused = nil; dismiss() }
    catch { message = BackendErrorMessage.text(error) }
  }
}
