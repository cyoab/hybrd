import SwiftUI
import WatchKit

@main
struct HybrdWatchApp: App {
  @WKApplicationDelegateAdaptor(WorkoutRecoveryDelegate.self) private var recoveryDelegate
  @State private var companion = CompanionBridge()
  @State private var recorder = RunRecorder.shared

  var body: some Scene {
    WindowGroup {
      ContentView().environment(companion).environment(recorder)
        .environment(\.trainingUnits, companion.snapshot?.units ?? .metric)
        .task { await recorder.recover() }
    }
  }
}

final class WorkoutRecoveryDelegate: NSObject, WKApplicationDelegate {
  func handleActiveWorkoutRecovery() {
    Task { @MainActor in await RunRecorder.shared.recover() }
  }
}
