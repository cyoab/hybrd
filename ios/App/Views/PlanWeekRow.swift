import SwiftUI

struct PlanWeekRow: View {
  var week: Date
  @Binding var selectedDate: Date
  var workouts: [TrainingWorkout]
  var results: [WorkoutResult]
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .body) private var dayHeight = 82

  var body: some View {
    GeometryReader { geometry in
      let inset: CGFloat = geometry.size.width < 340 ? 4 : 12
      let spacing = max(0, min(6, (geometry.size.width - inset * 2 - 7 * 44) / 6))
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing),
        count: typeSize.isAccessibilitySize ? 4 : 7), spacing: 8) {
        ForEach(0..<7) { offset in
          dayButton(TrainingEngine.date(week, offset: offset))
        }
      }
      .padding(.horizontal, inset)
    }
  }

  private func dayButton(_ day: Date) -> some View {
    let selected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
    let today = Calendar.current.isDateInToday(day)
    let daySessions = workouts.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    return Button { selectedDate = day } label: {
      VStack(spacing: 9) {
        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
          .font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
          .foregroundStyle(selected ? HybrdStyle.primaryButtonText.opacity(0.8) : HybrdStyle.muted)
        Text(day.formatted(.dateTime.day()))
          .font(.title3.weight(.semibold)).monospacedDigit()
          .foregroundStyle(selected ? HybrdStyle.primaryButtonText : HybrdStyle.ink)
        HStack(spacing: 3) {
          ForEach(daySessions.prefix(3)) { workout in
            let result = results.first { $0.logicalWorkoutID == workout.logicalID }
            DisciplineMark(kind: workout.kind,
              color: result != nil ? HybrdStyle.chartStone :
                (workout.kind == .run ? RunPalette.color(workout.resolvedRunType) : SessionPalette.violet), size: 6)
          }
          if daySessions.isEmpty { Color.clear.frame(width: 6, height: 6) }
        }
      }
      .frame(maxWidth: .infinity).frame(height: dayHeight)
      .background(selected ? HybrdStyle.primaryButton : HybrdStyle.surface.opacity(0.75),
        in: RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .strokeBorder(today && !selected ? HybrdStyle.terra : Color.clear, lineWidth: 1.5)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (today ? L10n.text(", today") : ""))
    .accessibilityValue(daySessions.isEmpty ? L10n.text("Recovery day") : daySessions.map { workout in
      workout.localizedTitle + (results.first { $0.logicalWorkoutID == workout.logicalID }.map { ", " + $0.status.displayName } ?? "")
    }.joined(separator: ". "))
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}
