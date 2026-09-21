import SwiftUI

struct RunPrescriptionView: View {
  var workout: TrainingWorkout

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Workout structure").font(.title3.weight(.semibold))
        Spacer()
        Text("\(workout.minutes) MIN").font(.caption2.weight(.medium)).tracking(1).foregroundStyle(HybrdStyle.muted)
      }
      ForEach(workout.segments.indices, id: \.self) { index in
        let segment = workout.segments[index]
        if !isPairedRecovery(index) {
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Text(segment.phase == .work && pairedRecovery(index) != nil ? "Repeat \(segment.repetitions ?? 1) times" : segment.displayTitle)
                .font(.subheadline.weight(.semibold))
              Spacer()
              if segment.phase == .work { Image(systemName: "repeat").accessibilityHidden(true) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(segment.phase == .work ? HybrdStyle.terraText : HybrdStyle.ink)
            .background(segment.phase == .work ? HybrdStyle.terraWash : HybrdStyle.field)

            stepContent(segment, showTitle: pairedRecovery(index) != nil)
            if let recovery = pairedRecovery(index) {
              Divider().padding(.horizontal, 16)
              stepContent(recovery, showTitle: true)
            }
          }
          .background(HybrdStyle.surface)
          .clipShape(RoundedRectangle(cornerRadius: 18))
          .overlay(RoundedRectangle(cornerRadius: 18).stroke(HybrdStyle.line))
        }
      }
    }
  }

  private func stepContent(_ segment: RunSegment, showTitle: Bool) -> some View {
    HStack(alignment: .top, spacing: 13) {
      Image(systemName: segment.phase == .recovery ? "figure.walk" : "figure.run")
        .foregroundStyle(segment.phase == .work ? HybrdStyle.terraText : HybrdStyle.muted)
        .frame(width: 22).padding(.top, 3).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 7) {
        if showTitle { Text(segment.title).font(.caption.weight(.medium)).foregroundStyle(HybrdStyle.muted) }
        Text(segment.targetSummary).font(.headline)
        Text(segment.cue).font(.subheadline).foregroundStyle(HybrdStyle.muted)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
    .accessibilityElement(children: .combine)
  }

  private func pairedRecovery(_ index: Int) -> RunSegment? {
    let segment = workout.segments[index]
    guard segment.phase == .work, (segment.repetitions ?? 1) > 1,
          workout.segments.indices.contains(index + 1) else { return nil }
    let recovery = workout.segments[index + 1]
    return recovery.phase == .recovery && recovery.repetitions == segment.repetitions ? recovery : nil
  }

  private func isPairedRecovery(_ index: Int) -> Bool {
    index > 0 && pairedRecovery(index - 1)?.id == workout.segments[index].id
  }
}
