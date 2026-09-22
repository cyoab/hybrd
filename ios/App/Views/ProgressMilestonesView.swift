import SwiftUI

struct ProgressMilestonesView: View {
  var milestones: [ProgressMilestone]
  var showAll = false
  @State private var selected: ProgressMilestone?
  @State private var showingCollection = false
  @Environment(\.dynamicTypeSize) private var typeSize

  private var featured: [ProgressMilestone] {
    let upcoming = milestones.filter { !$0.earned }.sorted {
      $0.fraction == $1.fraction ? $0.kind.target < $1.kind.target : $0.fraction > $1.fraction
    }
    let earned = milestones.filter(\.earned).sorted { $0.earnedAt! > $1.earnedAt! }
    return Array((Array(upcoming.prefix(2)) + earned + Array(upcoming.dropFirst(2))).prefix(4))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Your milestones").font(.title3.weight(.semibold))
          Text("\(milestones.filter(\.earned).count) of \(milestones.count) unlocked · all time")
            .font(.caption).foregroundStyle(HybrdStyle.muted)
        }
        Spacer(minLength: 8)
        if !showAll { Button("See all") { showingCollection = true }.font(.subheadline.weight(.medium)) }
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
        ForEach(showAll ? milestones : featured) { milestone in
          Button { selected = milestone } label: {
            VStack(spacing: 10) {
              ProgressMedalView(symbol: milestone.kind.symbol, tone: ProgressTheme.tone(milestone.kind), earned: milestone.earned)
                .frame(width: 88, height: 96)
              Text(milestone.kind.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
              Text(milestone.earned ? "Unlocked" : milestone.kind.progressLabel(milestone.value))
                .font(.caption2).foregroundStyle(milestone.earned ? SessionPalette.ink(ProgressTheme.tone(milestone.kind)) : HybrdStyle.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
              if !milestone.earned { ProgressView(value: milestone.fraction).tint(SessionPalette.color(ProgressTheme.tone(milestone.kind))) }
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 198, alignment: .top)
            .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 23))
            .contentShape(RoundedRectangle(cornerRadius: 23))
          }
          .buttonStyle(.plain)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(milestone.kind.title)
          .accessibilityValue(milestone.earned ? "Unlocked" : milestone.kind.progressLabel(milestone.value))
          .accessibilityHint("Shows the milestone and how it is earned")
        }
      }
    }
    .sensoryFeedback(.selection, trigger: selected?.id)
    .sheet(item: $selected) { ProgressMilestoneDetailView(milestone: $0) }
    .sheet(isPresented: $showingCollection) { ProgressMilestoneCollection(milestones: milestones) }
  }
}

private struct ProgressMilestoneCollection: View {
  @Environment(\.dismiss) private var dismiss
  var milestones: [ProgressMilestone]
  var body: some View {
    NavigationStack {
      ScrollView { ProgressMilestonesView(milestones: milestones, showAll: true).padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity) }
        .background(HybrdStyle.background).navigationTitle("Milestones").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
    }
  }
}
