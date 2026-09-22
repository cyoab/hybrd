import SwiftUI

struct ProgressJourneyView: View {
  var snapshot: ProgressSnapshot
  var explain: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("YOUR HYBRID JOURNEY").font(.caption2.weight(.semibold)).tracking(1.7)
          .foregroundStyle(SessionPalette.ink(.violet))
        Spacer()
        Button("How journey levels work", systemImage: "info.circle", action: explain)
          .labelStyle(.iconOnly).frame(width: 44, height: 44).foregroundStyle(HybrdStyle.muted)
      }
      let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) :
        AnyLayout(HStackLayout(spacing: 12))
      layout {
        ProgressMedalView(symbol: "sparkles", tone: .gold, level: snapshot.level)
          .frame(width: 124, height: 140)
        VStack(alignment: .leading, spacing: 8) {
          Text("LEVEL \(snapshot.level)").font(.caption.weight(.bold)).tracking(1.4)
            .foregroundStyle(SessionPalette.ink(.gold))
          Text(snapshot.levelTitle).font(.system(.title, design: .rounded, weight: .semibold)).tracking(-0.8)
            .fixedSize(horizontal: false, vertical: true)
          Text(snapshot.lifetime.activeDays == 0 ? "Your first session starts the story." :
            "\(snapshot.lifetime.activeDays) training days. Every one counts.")
            .font(.subheadline).foregroundStyle(HybrdStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Text("Next chapter").font(.caption.weight(.semibold))
          Spacer()
          Text("\(snapshot.levelSteps) / 10 days").font(.caption.monospacedDigit()).foregroundStyle(HybrdStyle.muted)
        }
        ProgressView(value: Double(snapshot.levelSteps), total: 10)
          .tint(SessionPalette.violet)
          .accessibilityLabel("Progress toward level \(snapshot.level + 1)")
        Text("\(snapshot.nextLevelIn) more training \(snapshot.nextLevelIn == 1 ? "day" : "days") to Level \(snapshot.level + 1). Rest days keep your progress intact.")
          .font(.caption).foregroundStyle(HybrdStyle.muted)
      }
      HStack(spacing: 20) {
        Label("\(snapshot.lifetime.runSessions) runs", systemImage: "figure.run").foregroundStyle(HybrdStyle.terraText)
        Label("\(snapshot.lifetime.liftSessions) lifts", systemImage: "dumbbell").foregroundStyle(SessionPalette.ink(.violet))
      }.font(.caption.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(20)
    .background(LinearGradient(colors: [SessionPalette.wash(.gold), HybrdStyle.surface, SessionPalette.wash(.violet)],
      startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 30))
    .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(SessionPalette.gold.opacity(0.18)))
  }
}
