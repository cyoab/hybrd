import SwiftUI

struct AppEntryView: View {
  @Environment(OnboardingStore.self) private var onboarding
  @Environment(TrainingStore.self) private var training
  @Environment(RunRecorder.self) private var recorder
  @Environment(BackendAppController.self) private var backend
  @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
  var body: some View {
    @Bindable var backend = backend
    Group {
      if recorder.recording != nil { ContentView() }
      else if backend.session.authenticated || backend.session.credential != nil {
        if backend.connected {
          if backend.needsOnboarding, let draft = backend.onboarding {
            NavigationStack {
              OnboardingJourneyView(onClose: { backend.showAccount = true }, onFinish: { backend.finishJourney() }, connectedAdvance: { complete in
                try await backend.saveOnboarding(complete: complete)
              }).environment(draft)
            }
          } else { ContentView() }
        } else {
          VStack(spacing: 20) {
            if backend.busy { ProgressView(L10n.text("Restoring your training…")) }
            if let error = backend.error { Text(error).multilineTextAlignment(.center) }
            Button(L10n.text("Try again")) { Task { await backend.connect(training: training) } }.disabled(backend.busy)
            Button(L10n.text("Account & sync")) { backend.showAccount = true }
          }.padding(24)
        }
      } else if onboarding.enteredApp || recorder.recording != nil { ContentView() }
      else { OnboardingEntryView { onboarding.enterApp() } }
    }
    .preferredColorScheme(appearance.colorScheme)
    .task { await backend.launch(training: training) }
    .sheet(isPresented: $backend.showAuthentication) { BackendEmailView() }
    .sheet(isPresented: $backend.showAccount) { BackendAccountView() }
    .onChange(of: recorder.recording?.id) { _, recordingID in
      if recordingID == nil, !backend.session.authenticated, backend.connected { backend.disconnect() }
    }
    .onChange(of: backend.session.authenticated) { _, authenticated in
      if !authenticated {
        if backend.connected { backend.sessionEnded() }
        onboarding.leaveApp()
      }
    }
  }
}
