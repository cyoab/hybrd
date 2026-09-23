import SwiftUI

struct CoachView: View {
  @Environment(TrainingStore.self) private var store
  @State private var question = ""
  @FocusState private var composing: Bool
  private let suggestions = [L10n.text("Why is my week arranged this way?"), L10n.text("I’m feeling tired"), L10n.text("How is my progress?")]

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
              Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
              Text(L10n.text("Your training, connected.")).font(.system(.title, design: .rounded, weight: .semibold)).tracking(-1)
              Text(L10n.text("Running and lifting, in the same conversation.")).foregroundStyle(.secondary)
              Label(L10n.text("On-device guidance"), systemImage: "iphone")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(HybrdStyle.surface, in: Capsule())
              Text(L10n.text("Cloud AI is not connected. These replies use simple rules and the training saved on this phone."))
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)

            if store.state.messages.isEmpty {
              ForEach(suggestions, id: \.self) { prompt in
                Button {
                  store.askCoach(prompt)
                } label: {
                  HStack {
                    Text(prompt).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                  }
                  .font(.subheadline.weight(.medium))
                  .padding(18)
                  .foregroundStyle(.primary)
                  .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
              }
            }
            ForEach(store.state.messages) { message in
              VStack(alignment: .leading, spacing: 9) {
                Text(message.isAthlete ? L10n.text("YOU") : L10n.text("HYBRD · ON DEVICE"))
                  .font(.caption2.bold()).tracking(1).foregroundStyle(.secondary)
                Text(message.text).font(.body).textSelection(.enabled)
              }
              .padding(18)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(message.isAthlete ? HybrdStyle.run.opacity(0.1) : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
              .id(message.id)
            }
          }
          .frame(maxWidth: 720, alignment: .leading)
          .frame(maxWidth: .infinity)
          .padding(20)
        }
        .onChange(of: store.state.messages.count) {
          if let last = store.state.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
      }
      .background(HybrdStyle.background)
      .navigationTitle(L10n.text("Coach"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(HybrdStyle.surface, for: .tabBar)
      .safeAreaInset(edge: .bottom) {
        HStack(alignment: .bottom, spacing: 12) {
          TextField(L10n.text("Ask about your training…"), text: $question, axis: .vertical)
            .lineLimit(1...5)
            .focused($composing)
            .padding(14)
            .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .submitLabel(.send)
            .onSubmit(send)
          Button(L10n.text("Send question"), systemImage: "arrow.up") { send() }
            .labelStyle(.iconOnly)
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
      }
    }
  }

  private func send() {
    store.askCoach(question)
    question = ""
    composing = false
  }
}
