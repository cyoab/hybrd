import SwiftUI

struct AppEntryView: View {
  @Environment(OnboardingStore.self) private var onboarding
  @Environment(RunRecorder.self) private var recorder
  @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

  var body: some View {
    Group {
      // A prototype must never hide a live/recovered recording behind sign-up.
      if onboarding.enteredApp || recorder.recording != nil { ContentView() }
      else { OnboardingEntryView { onboarding.enterApp() } }
    }.preferredColorScheme(appearance.colorScheme)
  }
}
