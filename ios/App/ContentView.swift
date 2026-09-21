import SwiftUI

struct ContentView: View {
  @Environment(TrainingStore.self) private var store

  var body: some View {
    @Bindable var store = store
    Group {
      if store.isLoaded {
        TabView {
          Tab("Today", systemImage: "sun.max.fill") { TodayView() }
          Tab("Plan", systemImage: "calendar") { PlanView() }
          Tab("Coach", systemImage: "bubble.left.and.bubble.right.fill") { CoachView() }
          Tab("Progress", systemImage: "chart.xyaxis.line") { TrainingProgressView() }
        }
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
