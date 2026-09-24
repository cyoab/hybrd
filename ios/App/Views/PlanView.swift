import SwiftUI

struct PlanView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dynamicTypeSize) private var dynamicType
  @State private var selectedDate = Calendar.current.startOfDay(for: Date())
  @State private var showProfile = false
  @State private var showCalendar = false
  @State private var showRunningWorkouts = false
  @State private var moving: TrainingWorkout?
  @State private var weekMode = false

  private var week: Date { TrainingEngine.startOfWeek(containing: selectedDate) }
  private var sessions: [TrainingWorkout] { store.sessions(in: week) }
  private var selectedSessions: [TrainingWorkout] {
    sessions.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
      .sorted { ($0.scheduledMinutes ?? 720) < ($1.scheduledMinutes ?? 720) }
  }
  private var firstWeek: Date {
    TrainingEngine.startOfWeek(containing: store.workouts.first?.date ?? Date())
  }
  private var weekNumber: Int {
    (Calendar.current.dateComponents([.day], from: firstWeek, to: week).day ?? 0) / 7 + 1
  }
  private var weekCount: Int {
    max(1, (Calendar.current.dateComponents([.day], from: firstWeek,
      to: TrainingEngine.startOfWeek(containing: store.workouts.last?.date ?? Date())).day ?? 0) / 7 + 1)
  }
  private var isInBlock: Bool { (1...weekCount).contains(weekNumber) }
  private var phase: String {
    if !isInBlock { return L10n.text("Calendar") }
    if weekNumber == weekCount { return L10n.text("Recovery") }
    return store.profile.isSample ? L10n.text("Build") : L10n.text("Base")
  }
  private var weekSummary: WeeklyTrainingSummary {
    WeeklyTrainingSummary(workouts: sessions, results: store.state.results)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(spacing: 20) {
            masthead.padding(.horizontal, 20)
            VStack(spacing: 14) {
              weekHeading.padding(.horizontal, 20)
              WeekCalendarView(selectedDate: $selectedDate, workouts: store.workouts, results: store.state.results)
            }
            VStack(alignment: .leading, spacing: 10) {
              Text(L10n.text("Logged this week")).font(.subheadline.weight(.medium)).foregroundStyle(HybrdStyle.muted)
              WeeklyProgressView(summary: weekSummary)
            }
            .padding(.horizontal, 20)
          }
          .padding(.top, 14)

          VStack(alignment: .leading, spacing: 24) {
            if weekMode {
              ForEach(0..<7) { offset in
                let day = TrainingEngine.date(week, offset: offset)
                let daySessions = sessions.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                  .sorted { ($0.scheduledMinutes ?? 720) < ($1.scheduledMinutes ?? 720) }
                VStack(alignment: .leading, spacing: 12) {
                  dayHeading(day)
                  if daySessions.isEmpty {
                    recoveryCard
                  } else {
                    ForEach(daySessions) { workout in
                      PlanSessionCard(workout: workout, expanded: workout.isKey, move: { moving = workout })
                    }
                  }
                }
              }
            } else {
              VStack(alignment: .leading, spacing: 14) {
                dayHeading(selectedDate)
                if selectedSessions.isEmpty {
                  recoveryCard
                } else {
                  ForEach(Array(selectedSessions.enumerated()), id: \.element.id) { index, workout in
                    PlanSessionCard(workout: workout, expanded: index == 0, move: { moving = workout })
                  }
                  trainingNote
                }
              }
            }
            if store.isBackendConnected && store.workouts.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("Your training setup is saved.")).font(.title3.bold())
                Text(L10n.text("Review a starter block in your athlete profile to put your first sessions on the calendar.")).foregroundStyle(HybrdStyle.muted)
                Button(L10n.text("Athlete profile")) { showProfile = true }.buttonStyle(HybrdPrimaryButtonStyle())
              }.padding(20).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 24))
            }
            bottomActions
          }
          .padding(.horizontal, 20)
        }
        .padding(.bottom, 28)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
      }
      .background {
        // Paint behind the entire viewport, including the status bar and sensor housing.
        // Content keeps its safe-area insets; only the background extends to the edges.
        LinearGradient(stops: [
          .init(color: HybrdStyle.terraWash.opacity(0.7), location: 0),
          .init(color: HybrdStyle.background, location: 0.5)
        ], startPoint: .top, endPoint: .bottom)
        .background(HybrdStyle.background)
        .ignoresSafeArea(.container)
      }
      .toolbar(.hidden, for: .navigationBar)
      .toolbarBackground(HybrdStyle.surface, for: .tabBar)
      .sheet(isPresented: $showProfile) { ProfileView() }
      .sheet(isPresented: $showCalendar) { calendarSheet }
      .sheet(isPresented: $showRunningWorkouts) {
        RunningWorkoutsView(selectedDate: selectedDate) { date in
          selectedDate = date
          showRunningWorkouts = false
        }
      }
      .sheet(item: $moving) { workout in
        MoveSessionView(workout: workout, expectedPlanID: store.plan.id)
      }
    }
  }

  private var masthead: some View {
    HStack(spacing: 12) {
      HybrdWordmark()
      Spacer(minLength: 8)
      if !dynamicType.isAccessibilitySize {
        Text(store.profile.isSample ? L10n.text("SAMPLE · \(phase.uppercased())") : isInBlock ? L10n.text("\(phase.uppercased()) · WK \(weekNumber) OF \(weekCount)") : L10n.text("YOUR PLAN"))
          .font(.caption2.weight(.medium)).tracking(0.8).foregroundStyle(HybrdStyle.muted)
          .lineLimit(2).multilineTextAlignment(.trailing)
      }
      Button { showProfile = true } label: {
        Text(initials)
          .font(.caption.weight(.medium))
          .foregroundStyle(HybrdStyle.primaryButtonText)
          .frame(width: 38, height: 38)
          .background(HybrdStyle.primaryButton, in: Circle())
          .padding(3)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(L10n.text("Athlete profile"))
    }
  }

  private var initials: String {
    let parts = store.profile.name.split(separator: " ")
    return String(parts.prefix(2).compactMap(\.first)).uppercased()
  }

  private var weekHeading: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(isInBlock ? L10n.text("Week \(weekNumber)") : L10n.text("Your calendar"))
          .font(.system(.title2, design: .rounded, weight: .semibold))
        Text(weekRange)
          .font(.caption.weight(.medium)).foregroundStyle(HybrdStyle.terraText)
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      Button { showCalendar = true } label: {
        Image(systemName: "calendar")
          .font(.body)
          .frame(width: 48, height: 48)
          .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 16))
      }
      .buttonStyle(.plain).accessibilityLabel(L10n.text("Choose a date"))
    }
  }

  private var weekRange: String {
    let end = TrainingEngine.date(week, offset: 6)
    let currentYear = Calendar.current.component(.year, from: Date())
    if Calendar.current.component(.year, from: week) != currentYear ||
       Calendar.current.component(.year, from: end) != currentYear {
      return week.formatted(.dateTime.day().month(.abbreviated).year()) + " – " +
        end.formatted(.dateTime.day().month(.abbreviated).year())
    }
    return week.formatted(.dateTime.day().month(.abbreviated)) + " – " +
      end.formatted(.dateTime.day().month(.abbreviated))
  }

  private func dayHeading(_ day: Date) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
        .font(.system(.title, design: .rounded, weight: .semibold)).tracking(-0.7)
      if Calendar.current.isDateInToday(day) {
        Text(L10n.text("TODAY")).font(.caption.weight(.medium)).tracking(1.4).foregroundStyle(HybrdStyle.terraText)
      }
      Spacer(minLength: 0)
    }
  }

  private var trainingNote: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "sparkles").foregroundStyle(HybrdStyle.terraText).padding(.top, 2).accessibilityHidden(true)
      Text(note).font(.subheadline).fixedSize(horizontal: false, vertical: true)
    }
    .padding(17)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HybrdStyle.terraWash, in: RoundedRectangle(cornerRadius: 20))
  }

  private var note: String {
    if store.plan.basePlanID != nil, store.plan.reason.hasPrefix("Moved") {
      return store.plan.localizedReason + L10n.text(". Your earlier plan is saved in plan history.")
    }
    if selectedSessions.contains(where: { $0.kind == .run && $0.isKey }) &&
       selectedSessions.contains(where: { $0.kind == .strength && $0.isOptional == true }) {
      return L10n.text("Your key run comes first. Upper-body strength is optional today, so you can leave room for recovery.")
    }
    return selectedSessions.first?.localizedPurpose ?? L10n.text("Recovery is part of the plan.")
  }

  private var recoveryCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: "leaf").font(.title).foregroundStyle(SessionPalette.ink(.mint))
        .frame(width: 64, height: 64).background(SessionPalette.mint.opacity(0.12), in: Circle())
        .accessibilityHidden(true)
      Text(L10n.text("Space to recover.")).font(.title2.weight(.semibold))
      Text(L10n.text("No session scheduled. Let the work settle in, and come back ready for what’s next."))
        .font(.subheadline).foregroundStyle(HybrdStyle.muted)
    }
    .padding(22).frame(maxWidth: .infinity, alignment: .leading)
    .background(SessionPalette.wash(.mint), in: RoundedRectangle(cornerRadius: 26))
  }

  private var bottomActions: some View {
    VStack(spacing: 18) {
      Button { showRunningWorkouts = true } label: {
        HStack(spacing: 14) {
          Image(systemName: "figure.run").font(.title2)
            .foregroundStyle(RunPalette.ink(.easy))
            .frame(width: 48, height: 48).background(RunPalette.top(.easy), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text("Running workouts")).font(.headline)
            Text(L10n.text("Find a run for your day")).font(.caption).foregroundStyle(HybrdStyle.muted)
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
        }
        .padding(17).frame(maxWidth: .infinity, alignment: .leading)
        .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 22))
        .contentShape(RoundedRectangle(cornerRadius: 22))
      }
      .buttonStyle(.plain)

      if store.profile.isSample {
        Button { showProfile = true } label: {
          HStack {
            VStack(alignment: .leading, spacing: 5) {
              Text(L10n.text("Make this plan yours")).font(.subheadline.weight(.semibold))
              Text(L10n.text("You’re exploring a sample block.")).font(.caption).foregroundStyle(HybrdStyle.muted)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.subheadline)
          }
          .padding(17).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
      }
      HStack {
        Button(weekMode ? L10n.text("Show selected day") : L10n.text("See the full week"), systemImage: weekMode ? "calendar" : "list.bullet") { weekMode.toggle() }
          .frame(minHeight: 44)
        Spacer()
        NavigationLink { PlanHistoryView() } label: { Image(systemName: "clock.arrow.circlepath") }
          .frame(minWidth: 44, minHeight: 44).accessibilityLabel(L10n.text("Plan history"))
      }
      .font(.subheadline).foregroundStyle(HybrdStyle.muted)
      if !Calendar.current.isDateInToday(selectedDate) {
        Button(L10n.text("Back to today")) { selectedDate = Calendar.current.startOfDay(for: Date()) }
          .font(.subheadline.weight(.medium)).foregroundStyle(HybrdStyle.terraText).frame(minHeight: 44)
      }
    }
  }

  private var calendarSheet: some View {
    NavigationStack {
      VStack {
        DatePicker(L10n.text("Training date"), selection: $selectedDate, displayedComponents: .date)
          .datePickerStyle(.graphical).padding()
        Button(L10n.text("Go to today")) { selectedDate = Calendar.current.startOfDay(for: Date()); showCalendar = false }
        Spacer()
      }
      .navigationTitle(L10n.text("Choose a day"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { showCalendar = false } } }
    }.presentationDetents([.medium, .large])
  }

}
