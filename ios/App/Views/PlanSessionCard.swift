import SwiftUI

struct PlanSessionCard: View {
  @Environment(TrainingStore.self) private var store
  var workout: TrainingWorkout
  var expanded: Bool
  var move: () -> Void

  private var result: WorkoutResult? { store.result(for: workout) }
  private var canMove: Bool { result == nil && !store.hasDraft(for: workout) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 9) {
        DisciplineMark(kind: workout.kind, size: 9)
        Text(category.uppercased()).font(.caption2.weight(.medium)).tracking(1.2)
          .foregroundStyle(workout.isKey ? HybrdStyle.terraText : HybrdStyle.muted)
        Spacer(minLength: 4)
        if let time = workout.scheduledTimeLabel {
          Text(time).font(.caption.monospacedDigit()).foregroundStyle(HybrdStyle.muted)
        }
      }
      NavigationLink {
        WorkoutDetailView(workout: workout)
      } label: {
        VStack(alignment: .leading, spacing: 8) {
          Text(workout.title).font(.system(.title2, design: .rounded, weight: .semibold)).tracking(-0.6)
            .foregroundStyle(HybrdStyle.ink)
          Text(workout.summary + (workout.kind == .run ? " · " + workout.prescriptionTarget : ""))
            .font(.subheadline).foregroundStyle(HybrdStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if expanded && workout.kind == .run && result == nil {
        VStack(spacing: 9) {
          ForEach(workout.segments) { segment in
            RunStepSummary(segment: segment)
          }
        }
      }

      if let result {
        Label(result.status.rawValue, systemImage: result.status == .skipped ? "forward.end" : "checkmark")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(HybrdStyle.terraText)
      } else if expanded {
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
    }
    .padding(18)
    .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    .overlay(RoundedRectangle(cornerRadius: 22).stroke(workout.isKey && result == nil ? HybrdStyle.terra : HybrdStyle.line, lineWidth: 1))
    .shadow(color: .black.opacity(workout.isKey ? 0.025 : 0), radius: 15, y: 8)
  }

  private var category: String {
    if let result { return result.status.rawValue + " · " + workout.kind.rawValue }
    if store.hasDraft(for: workout) { return "In progress · " + workout.kind.rawValue }
    return (workout.isKey ? "Key session · " : workout.isOptional == true ? "Optional · " : "") + workout.kind.rawValue
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

struct RunStepSummary: View {
  @Environment(\.dynamicTypeSize) private var dynamicType
  var segment: RunSegment

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      RoundedRectangle(cornerRadius: 2)
        .fill(SessionPalette.color(SessionBreakdown.tone(for: segment.heartRateZone)))
        .frame(width: 3, height: 20).accessibilityHidden(true)
      if dynamicType.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 5) {
          Text(segment.displayTitle).foregroundStyle(HybrdStyle.muted)
          Text(segment.targetSummary)
        }
      } else {
        Text(segment.displayTitle).foregroundStyle(HybrdStyle.muted)
        Spacer(minLength: 8)
        Text(segment.targetSummary).multilineTextAlignment(.trailing)
      }
    }
    .font(.subheadline)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
