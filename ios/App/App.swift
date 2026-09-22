import SwiftUI

@main
struct HybrdApp: App {
  @State private var recorder = RunRecorder.shared
  @State private var store = TrainingStore()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(store)
        .environment(recorder)
        .task { await recorder.recover() }
    }
  }
}
