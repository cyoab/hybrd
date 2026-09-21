import SwiftUI

struct TodayView: View {
  @Environment(TrainingStore.self) private var store
  @State private var showProfile = false
  private var week: [TrainingWorkout] { store.sessions(in: TrainingEngine.startOfWeek(containing: Date())) }
  private var today: [TrainingWorkout] {
    store.workouts.filter { Calendar.current.isDateInToday($0.date) }
  }
  private var nextWorkout: TrainingWorkout? {
    today.first { store.result(for: $0) == nil } ?? store.workouts.first {
      $0.date >= Calendar.current.startOfDay(for: Date()) && store.result(for: $0) == nil
    }
  }
  private var completedCount: Int {
    week.filter { store.result(for: $0).map { $0.status != .skipped } ?? false }.count
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          heading
          if store.profile.isSample { sampleBanner }
          if let workout = nextWorkout {
            sessionCard(workout)
          } else {
            ContentUnavailableView("Room to recover", systemImage: "leaf.fill",
              description: Text("Your scheduled sessions are complete. Take a moment to recover or set up your next block in your profile."))
          }
          weekSummary
          HStack(alignment: .top, spacing: 14) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
              .font(.title2).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
              Text("One plan. Both sides of you.").font(.headline)
              Text("Easy running builds your engine. Strength builds your foundation. Your week makes room for both.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(20)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 22))
          goals
        }
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 28)
      }
      .background(HybrdStyle.background)
      .navigationTitle("hybrd")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text("hybrd").font(.system(.title2, design: .rounded, weight: .black)).italic().tracking(-1)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Athlete profile", systemImage: "person.fill") { showProfile = true }
        }
      }
      .sheet(isPresented: $showProfile) { ProfileView() }
    }
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 8) {
      Eyebrow(text: Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
      Text("Built for both.")
        .font(.system(.largeTitle, design: .rounded, weight: .bold))
        .tracking(-1)
      Text(store.profile.isSample ? "Your running. Your strength. One direction." : "Let’s get to work, \(store.profile.name).")
        .font(.subheadline).foregroundStyle(.secondary)
    }
  }

  private var sampleBanner: some View {
    Button { showProfile = true } label: {
      HStack(spacing: 10) {
        Image(systemName: "sparkle")
        Text("Sample week").fontWeight(.semibold)
        Spacer()
        Text("Make it yours").fontWeight(.medium)
        Image(systemName: "arrow.up.right")
      }
      .font(.caption)
      .padding(14)
      .foregroundStyle(.primary)
      .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
  }

  private func sessionCard(_ workout: TrainingWorkout) -> some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Label(Calendar.current.isDateInToday(workout.date) ? "TODAY’S SESSION" : "UP NEXT", systemImage: workout.kind.symbol)
          .font(.caption.weight(.bold)).tracking(1)
        Spacer()
        Text(workout.kind.rawValue.uppercased()).font(.caption2.bold())
          .padding(.horizontal, 10).padding(.vertical, 6)
          .overlay(Capsule().stroke(HybrdStyle.ink.opacity(0.25)))
      }
      HStack(alignment: .center) {
        Text(workout.title)
          .font(.system(.largeTitle, design: .rounded, weight: .bold))
          .tracking(-1)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 4)
        Image(systemName: workout.kind.symbol)
          .font(.system(size: 55, weight: .light))
          .rotationEffect(.degrees(-8))
          .accessibilityHidden(true)
      }
      HStack(alignment: .firstTextBaseline, spacing: 22) {
        if workout.kind == .run {
          cardMetric(value: String(format: "%.1f", Double(workout.distanceMeters) / 1_000), unit: "km")
        } else {
          cardMetric(value: "\(workout.exercises.count)", unit: "exercises")
        }
        cardMetric(value: "\(workout.minutes)", unit: "min")
      }
      Text(workout.effort).font(.subheadline.weight(.medium))
      NavigationLink {
        WorkoutDetailView(workout: workout)
      } label: {
        HStack {
          Text(store.hasDraft(for: workout) ? "Continue session" : "View session")
          Spacer()
          Image(systemName: "arrow.right")
        }
        .font(.headline)
        .padding(17)
        .foregroundStyle(HybrdStyle.lime)
        .background(HybrdStyle.ink, in: RoundedRectangle(cornerRadius: 16))
      }
      .buttonStyle(.plain)
    }
    .padding(24)
    .foregroundStyle(HybrdStyle.ink)
    .background(HybrdStyle.lime, in: RoundedRectangle(cornerRadius: 28))
  }

  private func cardMetric(value: String, unit: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      Text(value).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
      Text(unit).font(.subheadline)
    }.accessibilityElement(children: .combine)
  }

  private var weekSummary: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("The week, together").font(.title3.bold())
        Spacer()
        Text("\(completedCount)/\(week.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
          .accessibilityLabel("\(completedCount) of \(week.count) sessions logged")
      }
      HStack(alignment: .top, spacing: 8) {
        ForEach(0..<7) { day in
          let date = TrainingEngine.date(TrainingEngine.startOfWeek(containing: Date()), offset: day)
          let sessions = week.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
          VStack(spacing: 10) {
            Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Image(systemName: sessions.first?.kind.symbol ?? "minus")
              .font(.body.weight(.medium))
              .frame(maxWidth: .infinity)
              .frame(height: 40)
              .background(Calendar.current.isDateInToday(date) ? HybrdStyle.lime : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 12))
              .foregroundStyle(Calendar.current.isDateInToday(date) ? HybrdStyle.ink : Color.primary)
            Circle()
              .fill(sessions.contains { store.result(for: $0)?.status == .completed } ? HybrdStyle.run : Color.clear)
              .frame(width: 4, height: 4)
          }
          .frame(maxWidth: .infinity)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide))): \(sessions.first?.title ?? "Recovery")")
        }
      }
      HStack(spacing: 10) {
        Label("\(week.filter { $0.kind == .run }.count) runs", systemImage: "figure.run")
        Text("·")
        Label("\(week.filter { $0.kind == .strength }.count) lifts", systemImage: "dumbbell.fill")
      }
      .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var goals: some View {
    VStack(alignment: .leading, spacing: 12) {
      Eyebrow(text: "The bigger picture")
      HStack {
        VStack(alignment: .leading, spacing: 6) {
          Text(store.profile.runningGoal.rawValue).font(.headline)
          Text(store.profile.strengthGoal.rawValue).font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer()
        Text(store.profile.priority.rawValue).font(.caption.weight(.medium))
          .padding(10).background(HybrdStyle.surface, in: Capsule())
      }
    }
  }
}
