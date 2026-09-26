import SwiftUI

struct WeekCalendarView: View {
  @Binding var selectedDate: Date
  var workouts: [TrainingWorkout]
  var results: [WorkoutResult]
  @State private var window: TrainingWeekWindow
  @State private var visibleWeek: Date?
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .body) private var dayHeight = 82

  init(selectedDate: Binding<Date>, workouts: [TrainingWorkout], results: [WorkoutResult]) {
    _selectedDate = selectedDate
    self.workouts = workouts
    self.results = results
    let window = TrainingWeekWindow(containing: selectedDate.wrappedValue)
    _window = State(initialValue: window)
    _visibleWeek = State(initialValue: window.startOfWeek(containing: selectedDate.wrappedValue))
  }

  var body: some View {
    VStack(spacing: 10) {
      ScrollView(.horizontal) {
        LazyHStack(spacing: 0) {
          ForEach(window.weeks, id: \.self) { week in
            PlanWeekRow(week: week, selectedDate: $selectedDate, workouts: workouts, results: results)
              .containerRelativeFrame(.horizontal)
              .id(week)
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
      .scrollPosition(id: $visibleWeek, anchor: .center)
      .frame(height: typeSize.isAccessibilitySize ? dayHeight * 2 + 8 : dayHeight)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(L10n.text("Weekly calendar"))
      .accessibilityAction(named: Text(L10n.text("Next week"))) { shiftWeek(1) }
      .accessibilityAction(named: Text(L10n.text("Previous week"))) { shiftWeek(-1) }

      Text(L10n.text("Swipe to explore weeks"))
        .font(.caption2).foregroundStyle(HybrdStyle.muted)
        .accessibilityHidden(true)
    }
    .onChange(of: visibleWeek) { _, newWeek in
      guard let newWeek, newWeek != window.startOfWeek(containing: selectedDate) else { return }
      selectedDate = window.selection(in: newWeek, matching: selectedDate)
      window.reveal(newWeek)
    }
    .onChange(of: selectedDate) { _, date in
      window.reveal(date)
      let week = window.startOfWeek(containing: date)
      if visibleWeek != week { visibleWeek = week }
    }
  }

  private func shiftWeek(_ direction: Int) {
    selectedDate = window.addingDays(direction * 7, to: selectedDate)
  }
}
