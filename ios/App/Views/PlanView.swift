import SwiftUI

struct PlanView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dynamicTypeSize) private var dynamicType
  @State private var selectedDate = Calendar.current.startOfDay(for: Date())
  @State private var showProfile = false
  @State private var showCalendar = false
  @State private var moving: TrainingWorkout?
  @State private var weekMode = false
  @ScaledMetric(relativeTo: .body) private var dayStripHeight = 82

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
    if !isInBlock { return "Calendar" }
    if weekNumber == weekCount { return "Recovery" }
    return store.profile.isSample ? "Build" : "Base"
  }
  private var weekSummary: String {
    let planned = Double(sessions.reduce(0) { $0 + $1.distanceMeters }) / 1_000
    let results = sessions.compactMap { store.result(for: $0) }
    let actual = Double(results.reduce(0) { $0 + ($1.distanceMeters ?? 0) }) / 1_000
    let lifts = results.filter { $0.kind == .strength && $0.status != .skipped }.count
    return "\(actual.formatted(.number.precision(.fractionLength(0...1)))) / \(planned.formatted(.number.precision(.fractionLength(0...1)))) km · \(lifts) of \(sessions.filter { $0.kind == .strength }.count) lifts done"
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          masthead
          VStack(spacing: 12) {
            weekNavigation
            dayStrip
          }
          Text(weekSummary).font(.subheadline).foregroundStyle(HybrdStyle.muted)

          if weekMode {
            ForEach(0..<7) { offset in
              let day = TrainingEngine.date(week, offset: offset)
              let daySessions = sessions.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
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
          bottomActions
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 28)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
      }
      .background(HybrdStyle.background.ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
      .toolbarBackground(HybrdStyle.surface, for: .tabBar)
      .sheet(isPresented: $showProfile) { ProfileView() }
      .sheet(isPresented: $showCalendar) { calendarSheet }
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
        Text(store.profile.isSample ? "SAMPLE · \(phase.uppercased())" : "\(phase.uppercased()) · WK \(weekNumber) OF \(weekCount)")
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
      .accessibilityLabel("Athlete profile")
    }
  }

  private var initials: String {
    let parts = store.profile.name.split(separator: " ")
    return String(parts.prefix(2).compactMap(\.first)).uppercased()
  }

  private var weekNavigation: some View {
    HStack(spacing: 2) {
      Button("Previous week", systemImage: "arrow.left") { shiftWeek(-1) }
        .labelStyle(.iconOnly).frame(width: 44, height: 44)
        .foregroundStyle(HybrdStyle.muted)
      Spacer(minLength: 0)
      VStack(spacing: 7) {
        Text(isInBlock ? "Week \(weekNumber)" : "Your calendar")
          .font(.headline)
        Text("\(phase.uppercased()) · \(week.formatted(.dateTime.day()))–\(TrainingEngine.date(week, offset: 6).formatted(.dateTime.day().month(.abbreviated)).uppercased())")
          .font(.caption2.weight(.medium)).tracking(1).foregroundStyle(HybrdStyle.terraText)
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      Button("Next week", systemImage: "arrow.right") { shiftWeek(1) }
        .labelStyle(.iconOnly).frame(width: 44, height: 44)
        .foregroundStyle(HybrdStyle.muted)
      Button { showCalendar = true } label: {
        Image(systemName: "calendar")
          .frame(width: 44, height: 44)
          .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 15))
          .overlay(RoundedRectangle(cornerRadius: 15).stroke(HybrdStyle.line))
      }
      .buttonStyle(.plain).accessibilityLabel("Choose a date")
    }
  }

  private var dayStrip: some View {
    GeometryReader { geometry in
      let cellWidth = dynamicType.isAccessibilitySize ? 72.0 : max(44, (geometry.size.width - 36) / 7)
      ScrollView(.horizontal) {
        HStack(spacing: 6) {
          ForEach(0..<7) { offset in
            let day = TrainingEngine.date(week, offset: offset)
            dayButton(day).frame(width: cellWidth)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .frame(height: dayStripHeight)
  }

  private func dayButton(_ day: Date) -> some View {
    let selected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
    let daySessions = sessions.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    return Button { selectedDate = day } label: {
      VStack(spacing: 10) {
        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
          .font(.system(.caption2, design: .default, weight: .medium))
          .foregroundStyle(selected ? Color.white.opacity(0.7) : HybrdStyle.muted)
        Text(day.formatted(.dateTime.day()))
          .font(.title3.weight(.semibold)).monospacedDigit()
          .foregroundStyle(selected ? Color.white : HybrdStyle.ink)
        HStack(spacing: 3) {
          ForEach(daySessions.prefix(3)) { workout in
            DisciplineMark(kind: workout.kind,
              color: store.result(for: workout) != nil ? HybrdStyle.stone : (workout.kind == .run ? HybrdStyle.terra : (selected ? .white : HybrdStyle.ink)),
              size: 7)
          }
          if daySessions.isEmpty { Color.clear.frame(width: 7, height: 7) }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(selected ? HybrdStyle.obsidian : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.clear : HybrdStyle.line))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(daySessions.count) sessions")
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }

  private func dayHeading(_ day: Date) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
        .font(.system(.title, design: .rounded, weight: .semibold)).tracking(-0.7)
      if Calendar.current.isDateInToday(day) {
        Text("TODAY").font(.caption.weight(.medium)).tracking(1.4).foregroundStyle(HybrdStyle.terraText)
      }
      Spacer(minLength: 0)
    }
  }

  private var trainingNote: some View {
    HStack(alignment: .top, spacing: 12) {
      Circle().fill(HybrdStyle.terra).frame(width: 7, height: 7).padding(.top, 6).accessibilityHidden(true)
      Text(note).font(.subheadline).fixedSize(horizontal: false, vertical: true)
    }
    .padding(17)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(HybrdStyle.terraWash, in: RoundedRectangle(cornerRadius: 20))
  }

  private var note: String {
    if store.plan.basePlanID != nil, store.plan.reason.hasPrefix("Moved") {
      return store.plan.reason + ". Your earlier plan is saved in plan history."
    }
    if selectedSessions.contains(where: { $0.kind == .run && $0.isKey }) &&
       selectedSessions.contains(where: { $0.kind == .strength && $0.isOptional == true }) {
      return "Your key run comes first. Upper-body strength is optional today, so you can leave room for recovery."
    }
    return selectedSessions.first?.purpose ?? "Recovery is part of the plan."
  }

  private var recoveryCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: "leaf").font(.title2).foregroundStyle(HybrdStyle.muted)
      Text("Space to recover.").font(.title2.weight(.semibold))
      Text("No session scheduled. Let the work settle in, and come back ready for what’s next.")
        .font(.subheadline).foregroundStyle(HybrdStyle.muted)
    }
    .padding(22).frame(maxWidth: .infinity, alignment: .leading)
    .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    .overlay(RoundedRectangle(cornerRadius: 22).stroke(HybrdStyle.line))
  }

  private var bottomActions: some View {
    VStack(spacing: 18) {
      if store.profile.isSample {
        Button { showProfile = true } label: {
          HStack {
            VStack(alignment: .leading, spacing: 5) {
              Text("Make this plan yours").font(.subheadline.weight(.semibold))
              Text("You’re exploring a sample block.").font(.caption).foregroundStyle(HybrdStyle.muted)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.subheadline)
          }
          .padding(17).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
      }
      HStack {
        Button(weekMode ? "Show selected day" : "See the full week", systemImage: weekMode ? "calendar" : "list.bullet") { weekMode.toggle() }
        Spacer()
        NavigationLink { PlanHistoryView() } label: { Image(systemName: "clock.arrow.circlepath") }
          .accessibilityLabel("Plan history")
      }
      .font(.subheadline).foregroundStyle(HybrdStyle.muted)
      if !Calendar.current.isDateInToday(selectedDate) {
        Button("Back to today") { selectedDate = Calendar.current.startOfDay(for: Date()) }
          .font(.subheadline.weight(.medium)).foregroundStyle(HybrdStyle.terraText)
      }
    }
  }

  private var calendarSheet: some View {
    NavigationStack {
      VStack {
        DatePicker("Training date", selection: $selectedDate, displayedComponents: .date)
          .datePickerStyle(.graphical).padding()
        Button("Go to today") { selectedDate = Calendar.current.startOfDay(for: Date()); showCalendar = false }
        Spacer()
      }
      .navigationTitle("Choose a day")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showCalendar = false } } }
    }.presentationDetents([.medium, .large])
  }

  private func shiftWeek(_ direction: Int) {
    selectedDate = TrainingEngine.date(selectedDate, offset: direction * 7)
  }
}
