import SwiftUI

struct CoachSettingsView: View {
  @Environment(BackendAppController.self) private var backend
  @Environment(\.dismiss) private var dismiss
  @State private var consentConfirmation = false
  @State private var editing = false
  @State private var memoryID = UUID()
  @State private var revision: BackendRevision?
  @State private var content = ""
  @State private var category: BackendWire.AgentMemoryInputCategory = .trainingPreference
  @State private var expires = false
  @State private var expiry = Date().addingTimeInterval(604800)
  @State private var forgetting: BackendWire.AgentMemory?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle(L10n.text("Cloud AI coaching"), isOn: Binding(get: { backend.cloudAIConsent }, set: { value in
            if value { consentConfirmation = true } else { Task { await backend.setCloudAIConsent(false) } }
          })).disabled(backend.busy || backend.pendingCount > 0)
          Text(L10n.text("With your permission, hybrd sends your questions and relevant saved training, profile, and memory to cloud AI providers through OpenRouter. A scope router checks whether questions relate to training. Exact GPS routes are excluded.")).font(.footnote).foregroundStyle(.secondary)
          Text(L10n.text("Replies and requests are saved to your account and this device. You can turn off cloud coaching here. Apple Health access is a separate permission.")).font(.footnote).foregroundStyle(.secondary)
        } header: { Text(L10n.text("Your choice")) }
        if let coach = backend.coach {
          Section {
            Text(L10n.text("You decide what your coach remembers. These notes are used in future replies; your workout history stays separate.")).font(.footnote).foregroundStyle(.secondary)
            ForEach(coach.memories, id: \.id) { memory in
              Button {
                memoryID = memory.id; revision = memory.revision; content = memory.content; category = memory.category
                expires = memory.expiresAt != nil; expiry = memory.expiresAt?.date ?? Date().addingTimeInterval(604800); editing = true
              } label: {
                VStack(alignment: .leading, spacing: 5) {
                  Text(memory.content).foregroundStyle(.primary)
                  if let end = memory.expiresAt { Text(end.date, style: .date).font(.caption).foregroundStyle(.secondary) }
                }
              }.swipeActions { Button(L10n.text("Forget"), role: .destructive) { forgetting = memory } }
            }
            Button(L10n.text("Add a memory"), systemImage: "plus") {
              memoryID = UUID(); revision = nil; content = ""; category = .trainingPreference; expires = false; editing = true
            }.disabled(coach.busy || !backend.cloudAIConsent || coach.memories.count >= 20)
          } header: { Text(L10n.text("Coach memory")) }
          if let error = coach.error ?? backend.error { Section { Text(error).font(.footnote).foregroundStyle(.secondary); Button(L10n.text("Reload saved memories")) { Task { await coach.loadMemories() } } } }
        }
      }
      .navigationTitle(L10n.text("Coach settings"))
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
      .task { await backend.coach?.loadMemories() }
      .confirmationDialog(L10n.text("Allow cloud AI coaching?"), isPresented: $consentConfirmation, titleVisibility: .visible) {
        Button(L10n.text("Allow cloud coaching")) { Task { await backend.setCloudAIConsent(true) } }
      } message: { Text(L10n.text("Your questions and relevant training data will be shared with cloud AI providers to prepare personalized replies.")) }
      .confirmationDialog(L10n.text("Forget this memory?"), isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
        if let memory = forgetting { Button(L10n.text("Forget"), role: .destructive) { Task { await backend.coach?.forget(memory); forgetting = nil } } }
      } message: { Text(L10n.text("This removes the note from future coaching context and cancels pending replies. Your workout history is kept.")) }
      .sheet(isPresented: $editing) { editor }
    }.tint(HybrdStyle.terraText)
  }
  private var editor: some View {
    NavigationStack {
      Form {
        TextField(L10n.text("What should your coach remember?"), text: $content, axis: .vertical).lineLimit(3...8)
        Picker(L10n.text("Category"), selection: $category) {
          Text(L10n.text("Training preference")).tag(BackendWire.AgentMemoryInputCategory.trainingPreference)
          Text(L10n.text("Communication style")).tag(BackendWire.AgentMemoryInputCategory.communication)
          Text(L10n.text("Temporary constraint")).tag(BackendWire.AgentMemoryInputCategory.temporaryConstraint)
        }
        Toggle(L10n.text("Set an expiry date"), isOn: $expires)
        if expires { DatePicker(L10n.text("Remember until"), selection: $expiry, in: Date()..., displayedComponents: .date) }
        Text(L10n.text("Up to 500 characters. Saving a memory cancels pending replies so future answers use the new context.")).font(.footnote).foregroundStyle(.secondary)
        if let error = backend.coach?.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
      }
      .navigationTitle(L10n.text("Coach memory"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { editing = false } }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Save")) {
            Task {
              do {
                let date = expires ? try BackendInstant(ISO8601DateFormatter().string(from: expiry)) : nil
                if await backend.coach?.saveMemory(id: memoryID, input: .init(expectedRevision: revision, category: category, content: content.trimmingCharacters(in: .whitespacesAndNewlines), expiresAt: date)) == true { editing = false }
              } catch { backend.coach?.error = BackendErrorMessage.text(error) }
            }
          }.disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.count > 500 || backend.coach?.busy == true)
        }
      }
    }
  }
}
