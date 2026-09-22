import SwiftUI

struct ProgressMilestoneDetailView: View {
  var milestone: ProgressMilestone
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          Text(milestone.earned ? "YOU EARNED THIS" : "YOUR NEXT WIN").font(.caption.weight(.semibold)).tracking(2)
            .foregroundStyle(SessionPalette.ink(ProgressTheme.tone(milestone.kind)))
          ProgressMedalView(symbol: milestone.kind.symbol, tone: ProgressTheme.tone(milestone.kind), earned: milestone.earned)
            .frame(width: 210, height: 220).scaleEffect(appeared || reduceMotion ? 1 : 0.85)
          Text(milestone.kind.title).font(.system(.largeTitle, design: .rounded, weight: .semibold))
          Text(milestone.kind.requirement).font(.body).foregroundStyle(HybrdStyle.muted)
          if let date = milestone.earnedAt {
            Label("Unlocked " + date.formatted(date: .abbreviated, time: .omitted), systemImage: "checkmark.seal.fill")
              .font(.subheadline.weight(.medium)).foregroundStyle(SessionPalette.ink(ProgressTheme.tone(milestone.kind)))
          } else {
            ProgressView(value: milestone.fraction).tint(SessionPalette.color(ProgressTheme.tone(milestone.kind)))
              .accessibilityLabel(milestone.kind.progressLabel(milestone.value))
            Text(milestone.kind.progressLabel(milestone.value)).font(.headline)
          }
          Text("Built from your logged training. Take it at your own pace; rest days never reset this journey.")
            .font(.subheadline).foregroundStyle(HybrdStyle.muted)
        }
        .multilineTextAlignment(.center).padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity)
      }
      .background(LinearGradient(colors: [SessionPalette.wash(ProgressTheme.tone(milestone.kind)), HybrdStyle.background], startPoint: .top, endPoint: .bottom))
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
      .onAppear { withAnimation(reduceMotion ? nil : .bouncy(duration: 0.5)) { appeared = true } }
    }
  }
}
