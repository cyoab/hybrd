import SwiftUI

@main
struct HybrdApp: App {
  @State private var store = TrainingStore()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(store)
    }
  }
}
