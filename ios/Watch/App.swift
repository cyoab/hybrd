import SwiftUI

@main
struct HybrdWatchApp: App {
  @State private var companion = CompanionBridge()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(companion)
    }
  }
}
