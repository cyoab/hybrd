import SwiftUI

struct CoachHistoryView: View {
  @Environment(BackendAppController.self) private var backend
  @Environment(\.dismiss) private var dismiss
  private var threads: [BackendWire.CoachThreadRecord] {
    (backend.replica?.records ?? []).compactMap { change in
      if case .coachThread(let value) = change { return value.payload }; return nil
    }.sorted { $0.updatedAt.date > $1.updatedAt.date }
  }
  var body: some View {
    NavigationStack {
      List {
        ForEach(threads, id: \.id) { thread in
          NavigationLink {
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(messages(thread.id), id: \.id) { message in
                  VStack(alignment: .leading, spacing: 8) {
                    Text(message.role == .user ? L10n.text("YOU") : L10n.text("HYBRD · AI COACH")).font(.caption2.bold()).foregroundStyle(.secondary)
                    Text(message.content).textSelection(.enabled)
                  }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                Button(L10n.text("Continue conversation")) { backend.coach?.selectThread(thread.id); dismiss() }
                  .buttonStyle(.borderedProminent).disabled(backend.coach?.pending != nil)
              }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.background(HybrdStyle.background).navigationTitle(thread.title ?? L10n.text("Coach"))
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(thread.title ?? L10n.text("Conversation"))
              Text(thread.updatedAt.date, style: .date).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      .overlay { if threads.isEmpty { ContentUnavailableView(L10n.text("No conversations yet"), systemImage: "sparkles") } }
      .navigationTitle(L10n.text("Conversation history"))
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
      .task { await backend.refresh() }
      .refreshable { await backend.refresh() }
    }
  }
  private func messages(_ threadID: UUID) -> [BackendWire.CoachMessageRecord] {
    (backend.replica?.records ?? []).compactMap { change in
      if case .coachMessage(let value) = change, let message = value.payload, message.threadId == threadID { return message }; return nil
    }.sorted { $0.createdAt.date < $1.createdAt.date }
  }
}
