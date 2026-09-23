import SwiftUI

@main
struct HybrdApp: App {
  @State private var recorder = RunRecorder.shared
  @State private var store = TrainingStore()
  @State private var onboarding = OnboardingStore()

  var body: some Scene {
    WindowGroup {
      AppEntryView()
        .environment(onboarding)
        .environment(store)
        .environment(\.trainingUnits, store.profile.trainingUnits)
        .environment(recorder)
        .task { await recorder.recover() }
    }
  }
}
