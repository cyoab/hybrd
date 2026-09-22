import SwiftUI

struct PlanSessionCard: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  var workout: TrainingWorkout
  var expanded: Bool
  var move: () -> Void

  private var result: WorkoutResult? { store.result(for: workout) }
  private var canMove: Bool { result == nil && !store.hasDraft(for: workout) }
  private var accent: Color { workout.kind == .run ? RunPalette.color(workout.resolvedRunType) : SessionPalette.violet }
  private var ink: Color { workout.kind == .run ? RunPalette.ink(workout.resolvedRunType) : SessionPalette.ink(.violet) }
  private var wash: Color { workout.kind == .run ? RunPalette.wash(workout.resolvedRunType) : SessionPalette.wash(.violet) }
  private var categoryTitle: String { workout.kind == .run ? workout.resolvedRunType.title : workout.kind.rawValue }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      NavigationLink {
        WorkoutDetailView(workout: workout)
      } label: {
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(category, systemImage: workout.kind == .run ? workout.resolvedRunType.symbol : workout.kind.symbol)
              .font(.caption.weight(.semibold)).foregroundStyle(ink)
            Spacer(minLength: 0)
            if let time = workout.scheduledTimeLabel {
              Text(time).font(.caption.monospacedDigit()).foregroundStyle(HybrdStyle.muted)
            }
          }
          HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
              Text(workout.title)
                .font(.system(.title2, design: .rounded, weight: .semibold)).tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
              Text(workout.summary).font(.subheadline).foregroundStyle(HybrdStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize {
              Image(workout.kind == .run ? "SessionShoe" : "SessionDumbbell")
                .resizable().scaledToFit().frame(width: expanded ? 94 : 76, height: expanded ? 88 : 70)
                .accessibilityHidden(true)
            }
          }

          if workout.kind == .run {
            Label(workout.prescriptionTarget, systemImage: "heart")
              .font(.caption.weight(.semibold)).foregroundStyle(ink)
          } else if expanded {
            Text("\(workout.exercises.flatMap(\.sets).count) sets planned")
              .font(.caption.weight(.semibold)).foregroundStyle(ink)
          }
        }
        .foregroundStyle(HybrdStyle.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens session details")

      if let result {
        Label(result.status.rawValue, systemImage: result.status == .skipped ? "forward.end" : "checkmark")
          .font(.subheadline.weight(.medium)).foregroundStyle(ink)
      } else if expanded {
        if typeSize.isAccessibilitySize {
          VStack(spacing: 8) {
            openButton
            if canMove { Button("Move session", action: move).buttonStyle(HybrdSecondaryButtonStyle()) }
          }
        } else {
          sessionActions
        }
      }
    }
    .padding(18)
    .background {
      RoundedRectangle(cornerRadius: 26).fill(
        LinearGradient(colors: [wash, HybrdStyle.surface],
          startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 26)
        .strokeBorder(accent.opacity(workout.isKey && result == nil ? 0.3 : 0.12))
    }
  }

  private var sessionActions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        openButton
        if canMove { Button("Move", action: move).buttonStyle(HybrdSecondaryButtonStyle()) }
      }
      VStack(spacing: 8) {
        openButton
        if canMove { Button("Move session", action: move).buttonStyle(HybrdSecondaryButtonStyle()) }
      }
    }
  }

  private var category: String {
    if let result { return result.status.rawValue + " · " + categoryTitle }
    if store.hasDraft(for: workout) { return "In progress · " + categoryTitle }
    return (workout.isKey ? "Key session · " : workout.isOptional == true ? "Optional · " : "") + categoryTitle
  }

  private var openButton: some View {
    NavigationLink {
      WorkoutDetailView(workout: workout)
    } label: {
      Text(store.hasDraft(for: workout) ? "Continue session" : "Open session")
    }
    .buttonStyle(HybrdPrimaryButtonStyle())
  }
}
