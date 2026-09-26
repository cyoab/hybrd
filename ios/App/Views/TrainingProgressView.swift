import SwiftUI

struct TrainingProgressView: View {
  @Environment(BackendAppController.self) private var backend
  @Environment(TrainingStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("hybrd.progress.period") private var period: ProgressPeriod = .month
  @State private var showingHistory = false
  @State private var showingJourney = false
  @State private var selectedResult: WorkoutResult?
  @State private var selectedDay: ProgressSnapshot.Day?
  @State private var selectedMilestone: ProgressMilestone?
  @State private var refreshDate = Date()

  var body: some View {
    NavigationStack {
      TimelineView(.periodic(from: refreshDate, by: 60)) { _ in
        let local = store.progress(for: period)
        let snapshot = (backend.progress.flatMap { $0.periodDays.rawValue == period.rawValue ? try? BackendProgressMapping.apply($0, to: local) : nil }) ?? local
        ScrollView {
          VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 7) {
              Eyebrow(text: L10n.text("The work becomes you"))
              Text(snapshot.lifetime.sessions == 0 ? L10n.text("Your next chapter.") : L10n.text("Look at you go."))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1)
              Text(L10n.text("Running and strength. One evolving story.")).font(.subheadline).foregroundStyle(HybrdStyle.muted)
            }
            ProgressJourneyView(snapshot: snapshot) { showingJourney = true }
            if let latest = snapshot.latestMilestone {
              Button { selectedMilestone = latest } label: {
                HStack(spacing: 12) {
                  Image(systemName: "sparkles").font(.title2).foregroundStyle(SessionPalette.ink(.gold))
                  VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Latest milestone · ") + latest.kind.title).font(.subheadline.weight(.semibold))
                    Text(latest.earnedAt!.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(HybrdStyle.muted)
                  }
                  Spacer(minLength: 0)
                  Image(systemName: "chevron.right").font(.caption)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                  .background(SessionPalette.wash(.gold), in: RoundedRectangle(cornerRadius: 20))
              }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 16) {
              Picker(L10n.text("Progress period"), selection: $period) {
                ForEach(ProgressPeriod.allCases) { Text($0.title).tag($0) }
              }.pickerStyle(.segmented).labelsHidden()
              ProgressTotalsView(snapshot: snapshot)
              HStack {
                Label(L10n.text("\(snapshot.current.sessions) sessions"), systemImage: "checkmark.seal")
                Spacer()
                Text(L10n.text("\(snapshot.current.activeDays) active days"))
              }.font(.caption.weight(.medium)).foregroundStyle(HybrdStyle.muted)
              ProgressTrendView(snapshot: snapshot)
            }
            VStack(alignment: .leading, spacing: 16) {
              Text(L10n.text("See your change")).font(.title3.weight(.semibold))
              if snapshot.comparisons.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                  ProfileIllustration(artwork: .experience).frame(height: 112)
                  Text(L10n.text("A baseline worth building.")).font(.headline)
                  Text(L10n.text("Repeat a logged run distance and type, or a lift at the same rep count on another day. Your first-to-latest comparison will appear here."))
                    .font(.subheadline).foregroundStyle(HybrdStyle.muted)
                  if snapshot.lifetime.sessions == 0, let next = store.workouts.first(where: { $0.date >= Calendar.current.startOfDay(for: Date()) && store.result(for: $0) == nil }) {
                    NavigationLink(L10n.text("Open your next session")) { WorkoutDetailView(workout: next) }
                      .buttonStyle(HybrdPrimaryButtonStyle())
                  }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                  .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 25))
              } else {
                Text(L10n.text("First to latest comparable efforts · all time")).font(.caption).foregroundStyle(HybrdStyle.muted)
                ForEach(snapshot.comparisons) { ProgressComparisonView(comparison: $0) }
              }
            }
            ProgressRhythmView(days: snapshot.rhythm) { selectedDay = $0 }
            ProgressMilestonesView(milestones: snapshot.milestones)
            if !snapshot.results.isEmpty {
              VStack(alignment: .leading, spacing: 14) {
                HStack {
                  Text(L10n.text("The work behind it")).font(.title3.weight(.semibold))
                  Spacer()
                  Button(L10n.text("View all")) { showingHistory = true }.font(.subheadline)
                }
                ForEach(snapshot.results.prefix(3)) { result in
                  Button { selectedResult = result } label: {
                    ProgressHistoryRow(result: result, title: snapshot.workoutTitles[result.plannedWorkoutID] ?? result.kind.displayName)
                      .padding(12).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                  }.buttonStyle(.plain)
                }
              }
            }
            Text(L10n.text("Built from your logged activity. Partial sessions include only completed work. More volume isn’t automatically better fitness."))
              .font(.caption).foregroundStyle(HybrdStyle.muted)
          }
          .padding(20).padding(.bottom, 16).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(HybrdStyle.background)
        .sheet(isPresented: $showingHistory) { ProgressHistoryView(results: snapshot.results, workoutTitles: snapshot.workoutTitles) }
        .sheet(item: $selectedResult) { result in
          NavigationStack {
            ProgressResultDetailView(result: result, title: snapshot.workoutTitles[result.plannedWorkoutID] ?? result.kind.displayName)
              .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(L10n.text("Close"), systemImage: "xmark") { selectedResult = nil }.labelStyle(.iconOnly)
              } }
          }
        }
        .sheet(item: $selectedDay) { day in ProgressHistoryView(results: day.results.reversed(), workoutTitles: snapshot.workoutTitles, day: day.date) }
      }
      .navigationTitle(L10n.text("Progress")).navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(HybrdStyle.surface, for: .tabBar)
      .sheet(item: $selectedMilestone) { ProgressMilestoneDetailView(milestone: $0) }
      .sheet(isPresented: $showingJourney) { ProgressJourneyExplanation() }
      .task(id: "\(period.rawValue)-\(store.progressRevision)") { await backend.fetchProgress(days: period.rawValue) }
      .sensoryFeedback(.selection, trigger: period)
      .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDate = Date() } }
    }
  }
}

private struct ProgressJourneyExplanation: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          ProgressMedalView(symbol: "sparkles", tone: .gold, level: 1).frame(height: 170)
          Text(L10n.text("A journey built one day at a time.")).font(.system(.title, design: .rounded, weight: .semibold))
          Text(L10n.text("Each distinct day with a logged run or completed strength sets adds one step. Every 10 training days opens another level."))
          Text(L10n.text("Two workouts on the same day still count as one training day. Rest days don’t take away steps. Your level reflects logged consistency, not fitness or a ranking against other athletes."))
          Text(L10n.text("The calendar currently uses the date you log a result in your device’s time zone. It does not backdate activity to its planned date.")).font(.subheadline).foregroundStyle(HybrdStyle.muted)
          Text(L10n.text("Milestones are calculated from your current records. Correcting or deleting a record can update the totals and awards attached to it."))
            .font(.subheadline).foregroundStyle(HybrdStyle.muted)
        }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
      }
      .background(HybrdStyle.background).navigationTitle(L10n.text("Your journey")).navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Close"), systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
    }
  }
}
