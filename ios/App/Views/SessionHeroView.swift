import SwiftUI

struct SessionHeroView: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  var workout: TrainingWorkout

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 6) {
        VStack(alignment: .leading, spacing: 10) {
          Text((workout.isKey ? L10n.text("KEY SESSION · ") : workout.isOptional == true ? L10n.text("OPTIONAL · ") : "") + (workout.kind == .run ? workout.resolvedRunType.title : workout.kind.displayName).uppercased())
            .font(.caption.weight(.semibold)).tracking(1.3)
          Text(workout.localizedTitle)
            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1)
            .fixedSize(horizontal: false, vertical: true)
          Text(workout.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            + (workout.scheduledTimeLabel.map { " · " + $0 } ?? ""))
            .font(.subheadline)
        }
        .foregroundStyle(HybrdStyle.ink)
        .frame(maxWidth: .infinity, alignment: .leading)

        if !typeSize.isAccessibilitySize {
          Image(workout.kind == .run ? "SessionShoe" : "SessionDumbbell")
            .resizable().scaledToFit().frame(width: 94, height: 112)
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, 20).padding(.top, 18)

      SessionInfographicView(workout: workout)
    }
    .frame(maxWidth: 760).frame(maxWidth: .infinity)
    .background {
      LinearGradient(stops: [
        .init(color: workout.kind == .run ? RunPalette.top(workout.resolvedRunType) : SessionPalette.liftTop, location: 0),
        .init(color: workout.kind == .run ? RunPalette.wash(workout.resolvedRunType) : SessionPalette.liftGlow, location: 0.38),
        .init(color: HybrdStyle.background, location: 0.8)
      ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }
}
