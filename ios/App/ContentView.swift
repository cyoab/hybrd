import SwiftUI

struct ContentView: View {
  @Environment(TrainingStore.self) private var store

  var body: some View {
    Group {
      if store.isLoaded {
        TabView {
          Tab("Plan", systemImage: "calendar") { PlanView() }
          Tab("Progress", systemImage: "square.3.layers.3d") { TrainingProgressView() }
          Tab("Coach", systemImage: "sparkles") { CoachView() }
        }
        .tint(HybrdStyle.ink)
      } else {
        ContentUnavailableView {
          Label("Training data unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
          Text(store.loadError ?? "Opening your training data…")
        } actions: {
          Button("Try again") { store.load() }
        }
      }
    }
    .alert("Couldn’t save changes", isPresented: Binding(
      get: { store.errorMessage != nil },
      set: { if !$0 { store.errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { store.errorMessage = nil }
    } message: {
      Text(store.errorMessage ?? "")
    }
  }
}
