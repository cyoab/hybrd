import SwiftUI

struct WatchWorkoutCardView: View {
  @Environment(\.trainingUnits) private var units
  var workout: TrainingWorkout
  private var accent: Color { WatchRunStyle.workoutColor(workout) }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Image(systemName: workout.kind == .run ? workout.resolvedRunType.symbol : "dumbbell.fill")
        Text(workout.date.formatted(.dateTime.weekday(.abbreviated).day())).textCase(.uppercase)
        Spacer(minLength: 0)
        if workout.isKey { Image(systemName: "star.fill") }
      }.font(.caption2.weight(.semibold)).foregroundStyle(accent)
      HStack(spacing: 0) {
        Text(workout.localizedTitle).font(.headline).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        Image(workout.kind == .run ? "SessionShoe" : "SessionDumbbell")
          .resizable().scaledToFit().frame(width: 54, height: 50).accessibilityHidden(true)
      }
      Text(units.summary(workout)).font(.caption2).foregroundStyle(.white.opacity(0.85))
      if workout.kind == .run {
        WatchRunSequenceView(steps: RunTimeline(segments: workout.segments).steps).frame(height: 21)
        Text(workout.prescriptionTarget).font(.caption2.weight(.medium)).foregroundStyle(accent)
      } else {
        HStack(spacing: 3) {
          ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, exercise in
            RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.7)).frame(height: 7)
              .overlay { Text("\(exercise.sets.count)").hidden() }
          }
        }.accessibilityHidden(true)
        Text(L10n.text("\(workout.exercises.reduce(0) { $0 + $1.sets.count }) planned sets")).font(.caption2).foregroundStyle(accent)
      }
    }
    .padding(.vertical, 5)
    .accessibilityElement(children: .combine)
  }
}
