import SwiftUI

struct AppEntryView: View {
  @Environment(TrainingStore.self) private var training
  @Environment(RunRecorder.self) private var recorder
  @Environment(BackendAppController.self) private var backend
  @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
  @State private var showingRecoveredRun = false

  var body: some View {
    @Bindable var backend = backend
    Group {
      if backend.launching {
        ProgressView(L10n.text("Restoring your training…"))
          .frame(maxWidth: .infinity, maxHeight: .infinity).background(HybrdStyle.background)
      } else if !backend.session.authenticated {
        OnboardingEntryView()
      } else if backend.connected {
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
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if !backend.launching, (!backend.session.authenticated || !backend.connected), let run = recorder.recording {
        Button(run.isFinished ? L10n.text("Review your recorded run") : L10n.text("Return to active run"), systemImage: "figure.run") {
          showingRecoveredRun = true
        }.font(.subheadline).padding(14).frame(maxWidth: .infinity).background(HybrdStyle.terraWash)
      }
    }
    .preferredColorScheme(appearance.colorScheme)
    .task { await recorder.recover(); await backend.launch(training: training) }
    .sheet(isPresented: $backend.showAuthentication) { BackendEmailView() }
    .sheet(isPresented: $backend.showAccount) { BackendAccountView() }
    .fullScreenCover(isPresented: $showingRecoveredRun) {
      if let run = recorder.recording { RunSessionView(workout: run.workout) }
    }
    .onChange(of: recorder.recording?.id) { _, recordingID in
      if recordingID == nil {
        showingRecoveredRun = false
        if !backend.session.authenticated, backend.connected { backend.disconnect() }
      }
    }
    .onChange(of: backend.session.authenticated) { _, authenticated in
      if !authenticated { backend.sessionEnded() }
    }
  }
}
