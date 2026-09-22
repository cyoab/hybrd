import SwiftUI

struct ContentView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(RunRecorder.self) private var recorder
  @State private var showingRun = false
  @State private var showingWatchInbox = false
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

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
    .safeAreaInset(edge: .top, spacing: 0) {
      if let run = recorder.recording {
        Button { showingRun = true } label: {
          HStack { Label(run.isFinished ? "Review your recorded run" : "Return to active run", systemImage: "figure.run"); Spacer(); Image(systemName: "chevron.right") }
            .font(.subheadline.weight(.semibold)).padding(14).frame(maxWidth: .infinity).background(HybrdStyle.terraWash)
        }.buttonStyle(.plain)
      }
      if !store.companion.receivedRuns.isEmpty {
        Button("Review received Watch run", systemImage: "applewatch") { showingWatchInbox = true }
          .font(.subheadline).padding(8).frame(maxWidth: .infinity).background(HybrdStyle.surface)
      }
    }
    .fullScreenCover(isPresented: $showingRun) { if let run = recorder.recording { RunSessionView(workout: run.workout) } }
    .sheet(isPresented: $showingWatchInbox) { WatchRunInboxView() }
    .onChange(of: scenePhase) { _, phase in if phase == .active { store.companion.retryTransfers() } }
    .preferredColorScheme(appearance.colorScheme)
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
