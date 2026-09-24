import SwiftUI

@main
struct HybrdApp: App {
  @State private var recorder = RunRecorder.shared
  @State private var store = TrainingStore()
  @State private var backend = BackendAppController()

  var body: some Scene {
    WindowGroup {
      AppEntryView()
        .environment(backend)
        .environment(store)
        .environment(\.trainingUnits, store.profile.trainingUnits)
        .environment(recorder)
    }
  }
}
