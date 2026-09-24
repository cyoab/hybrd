import SwiftUI

struct ContentView: View {
  @Environment(BackendAppController.self) private var backend
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
          Tab(L10n.text("Plan"), systemImage: "calendar") { PlanView() }
          Tab(L10n.text("Progress"), systemImage: "square.3.layers.3d") { TrainingProgressView() }
          if !backend.connected { Tab(L10n.text("Coach"), systemImage: "sparkles") { CoachView() } }
        }
        .tint(HybrdStyle.ink)
      } else {
        ContentUnavailableView {
          Label(L10n.text("Training data unavailable"), systemImage: "externaldrive.badge.exclamationmark")
        } description: {
          Text(store.loadError ?? L10n.text("Opening your training data…"))
        } actions: {
          Button(L10n.text("Try again")) { store.load() }
        }
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if backend.connected {
        Button { backend.showAccount = true } label: {
          HStack {
            Text(backend.busy ? L10n.text("Syncing…") : backend.pendingCount > 0 ? L10n.text("Changes waiting to sync") : L10n.text("Account & sync"))
            Spacer()
            if backend.error != nil { Text(L10n.text("Needs attention")).foregroundStyle(HybrdStyle.terraText) }
          }.font(.caption).padding(.horizontal, 20).padding(.vertical, 8).frame(maxWidth: .infinity).background(HybrdStyle.surface)
        }.buttonStyle(.plain)
      }
      if let run = recorder.recording {
        Button { showingRun = true } label: {
          HStack { Label(run.isFinished ? L10n.text("Review your recorded run") : L10n.text("Return to active run"), systemImage: "figure.run"); Spacer(); Image(systemName: "chevron.right") }
            .font(.subheadline.weight(.semibold)).padding(14).frame(maxWidth: .infinity).background(HybrdStyle.terraWash)
        }.buttonStyle(.plain)
      }
      if !store.companion.receivedRuns.isEmpty {
        Button(L10n.text("Review received Watch run"), systemImage: "applewatch") { showingWatchInbox = true }
          .font(.subheadline).padding(8).frame(maxWidth: .infinity).background(HybrdStyle.surface)
      }
    }
    .fullScreenCover(isPresented: $showingRun) { if let run = recorder.recording { RunSessionView(workout: run.workout) } }
    .sheet(isPresented: $showingWatchInbox) { WatchRunInboxView() }
    .onChange(of: scenePhase) { _, phase in if phase == .active { store.companion.retryTransfers(); Task { await backend.refresh() } } }
    .preferredColorScheme(appearance.colorScheme)
    .alert(L10n.text("Couldn’t save changes"), isPresented: Binding(
      get: { store.errorMessage != nil },
      set: { if !$0 { store.errorMessage = nil } }
    )) {
      Button(L10n.text("OK"), role: .cancel) { store.errorMessage = nil }
    } message: {
      Text(store.errorMessage ?? "")
    }
  }
}
