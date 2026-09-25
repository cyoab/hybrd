import SwiftUI

struct CoachView: View {
  @Environment(BackendAppController.self) private var backend
  @Environment(\.scenePhase) private var scenePhase
  @State private var question = ""
  @State private var settings = false
  @State private var history = false
  @State private var resultID: UUID?
  @FocusState private var composing: Bool

  var body: some View {
    NavigationStack {
      Group {
        if let coach = backend.coach { conversation(coach) }
        else { ContentUnavailableView(L10n.text("Sign in to meet your coach"), systemImage: "sparkles") }
      }
      .background(HybrdStyle.background.ignoresSafeArea())
      .navigationTitle(L10n.text("Coach"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(L10n.text("New conversation"), systemImage: "square.and.pencil") { backend.coach?.newConversation(); resultID = nil }
            .disabled(backend.coach?.pending != nil)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button(L10n.text("Conversation history"), systemImage: "clock.arrow.circlepath") { history = true }
          Button(L10n.text("Coach settings"), systemImage: "slider.horizontal.3") { settings = true }
        }
      }
      .sheet(isPresented: $history) { CoachHistoryView() }
      .sheet(isPresented: $settings) { CoachSettingsView() }
      .task {
        await backend.coach?.refresh()
        if backend.cloudAIConsent { backend.coach?.resume() }
      }
      .onChange(of: backend.coach?.pending?.id) { old, new in
        if old != nil && new == nil { Task { await backend.refresh() } }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active {
          Task { await backend.coach?.refresh(); if backend.cloudAIConsent { backend.coach?.resume() } }
        } else { backend.coach?.suspend() }
      }
    }
  }
  private func canonicalMessages(_ thread: UUID) -> [BackendWire.CoachMessageRecord] {
    (backend.replica?.records ?? []).compactMap { change in
      if case .coachMessage(let value) = change, let message = value.payload, message.threadId == thread { return message }; return nil
    }.sorted { $0.createdAt.date < $1.createdAt.date }
  }
  private func conversation(_ coach: AgentRunStore) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          introduction(coach)
          if coach.currentEntries.isEmpty && canSend(coach) {
            ForEach([L10n.text("Why is my week arranged this way?"), L10n.text("I’m feeling tired"), L10n.text("How is my progress?")], id: \.self) { prompt in
              Button { question = prompt; send(coach) } label: {
                HStack { Text(prompt).multilineTextAlignment(.leading); Spacer(); Image(systemName: "arrow.up") }
                  .font(.subheadline.weight(.medium)).padding(18).frame(maxWidth: .infinity)
                  .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
              }.buttonStyle(.plain)
            }
          }
          if let id = coach.snapshot.threadID, coach.currentEntries.isEmpty {
            ForEach(canonicalMessages(id), id: \.id) { message in
              VStack(alignment: .leading, spacing: 7) {
                Text(message.role == .user ? L10n.text("YOU") : L10n.text("HYBRD · AI COACH")).font(.caption2.bold()).foregroundStyle(.secondary)
                Text(message.content).textSelection(.enabled)
              }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            }
          }
          ForEach(coach.currentEntries) { entry in
            VStack(alignment: .leading, spacing: 16) {
              VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("YOU")).font(.caption2.bold()).foregroundStyle(.secondary)
                Text(entry.request.message).textSelection(.enabled)
              }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(HybrdStyle.terraWash, in: RoundedRectangle(cornerRadius: 20))
              if let run = entry.run {
                if let artifact = run.artifact {
                  CoachArtifactView(artifact: artifact, stale: run.artifactStale)
                } else if AgentRunStore.Entry.terminal(run.status) {
                  Text(statusMessage(run.status)).font(.subheadline).foregroundStyle(.secondary)
                  if let code = run.errorCode { Text(code).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
                }
              }
              if let rejection = entry.rejection {
                Text(L10n.text("This request was not accepted. Review the message below before trying again.")).font(.subheadline)
                Text(rejection).font(.caption).foregroundStyle(.secondary)
              }
            }.id(entry.id)
          }
          if coach.pending != nil {
            HStack {
              ProgressView().accessibilityLabel(L10n.text("Coach is working"))
              Text(coach.activity ?? L10n.text("Connecting to your coach…")).font(.subheadline)
              Spacer()
              Button(L10n.text("Cancel request"), systemImage: "stop.fill") { coach.cancel() }.labelStyle(.iconOnly)
            }.padding(.vertical, 12)
          }
          if let error = coach.error ?? backend.error {
            VStack(alignment: .leading, spacing: 10) {
              Text(error).font(.subheadline).foregroundStyle(.secondary)
              Button(L10n.text("Try again"), systemImage: "arrow.clockwise") {
                Task { await coach.refresh(); if backend.cloudAIConsent { coach.resume() } }
              }
            }
          }
        }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: coach.snapshot.entries.count) { if let last = coach.snapshot.entries.last { proxy.scrollTo(last.id, anchor: .bottom) } }
      .safeAreaInset(edge: .bottom) { composer(coach) }
    }
  }
  private func introduction(_ coach: AgentRunStore) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(HybrdStyle.terraText).accessibilityHidden(true)
      Text(L10n.text("Your training, connected.")).font(.system(.title, design: .rounded, weight: .semibold))
      Text(L10n.text("An AI coach for your running and lifting. Grounded in the training you’ve saved.")).foregroundStyle(.secondary)
      Text(L10n.text("AI can make mistakes. Review its guidance. Your plan stays unchanged in this version.")).font(.caption).foregroundStyle(.secondary)
      if !coach.available {
        Text(L10n.text("Cloud coaching is not available on this server yet.")).font(.subheadline)
      } else if !backend.cloudAIConsent {
        Button(L10n.text("Meet your coach")) { settings = true }.buttonStyle(.borderedProminent)
      }
      if backend.pendingCount > 0 { Text(L10n.text("Sync your pending training changes before asking your coach.")).font(.caption).foregroundStyle(.secondary) }
    }.padding(.vertical, 10)
  }
  private func canSend(_ coach: AgentRunStore) -> Bool {
    coach.available && backend.cloudAIConsent && !backend.busy && backend.pendingCount == 0 && coach.pending == nil && !coach.busy
  }
  private var results: [(id: UUID, revision: BackendRevision, title: String)] {
    (backend.replica?.records ?? []).compactMap { change in
      guard case .workoutResult(let value) = change, let result = value.payload else { return nil }
      switch result {
      case .running(let r): return (r.id, r.revision, L10n.text("Run") + " · " + r.trainingDate.rawValue)
      case .strength(let r): return (r.id, r.revision, L10n.text("Strength") + " · " + r.trainingDate.rawValue)
      }
    }.sorted { $0.title > $1.title }
  }
  private func composer(_ coach: AgentRunStore) -> some View {
    VStack(spacing: 8) {
      if coach.capabilities?.tasks.analyzeWorkout == true && !results.isEmpty {
        Picker(L10n.text("Discuss a workout"), selection: $resultID) {
          Text(L10n.text("General conversation")).tag(UUID?.none)
          ForEach(results, id: \.id) { result in Text(result.title).tag(UUID?.some(result.id)) }
        }.pickerStyle(.menu).disabled(!canSend(coach))
      }
      HStack(alignment: .bottom, spacing: 10) {
        TextField(L10n.text("Ask about your training…"), text: $question, axis: .vertical)
          .lineLimit(1...5).focused($composing).padding(14)
          .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 18))
          .submitLabel(.send).onSubmit { send(coach) }
        Button(L10n.text("Send question"), systemImage: "arrow.up") { send(coach) }
          .labelStyle(.iconOnly).buttonStyle(.borderedProminent).buttonBorderShape(.circle).controlSize(.large)
          .disabled(!canSend(coach) || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.count > 4000)
      }
      if question.count > 4000 { Text(L10n.text("Keep your question under 4,000 characters.")).font(.caption).foregroundStyle(.red) }
    }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
  }
  private func send(_ coach: AgentRunStore) {
    guard canSend(coach) else { return }
    let text = question
    let result = results.first { $0.id == resultID }
    Task {
      let prior = coach.snapshot.entries.last?.id
      await coach.start(text, resultID: result?.id, revision: result?.revision)
      if coach.snapshot.entries.last?.id != prior { question = ""; composing = false }
    }
  }
  private func statusMessage(_ status: BackendWire.AgentRunStatus) -> String {
    switch status {
    case .cancelled: L10n.text("Request cancelled.")
    case .indeterminate: L10n.text("The connection ended before the provider confirmed an answer. This request won’t be retried automatically.")
    case .failed: L10n.text("Your coach couldn’t finish this request. You can send a new question.")
    default: L10n.text("No answer is available for this request.")
    }
  }
}
