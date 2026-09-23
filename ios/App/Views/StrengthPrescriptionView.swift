import SwiftUI

struct StrengthPrescriptionView: View {
  @Environment(\.trainingUnits) private var units
  @Environment(TrainingStore.self) private var store
  var exercises: [ExercisePrescription]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(L10n.text("Your lineup")).font(.title3.weight(.semibold))
        Spacer()
        Text(L10n.text("\(exercises.reduce(0) { $0 + $1.sets.count }) sets"))
          .font(.subheadline).foregroundStyle(HybrdStyle.muted)
      }.padding(.bottom, 8)

      ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
        DisclosureGroup {
          VStack(alignment: .leading, spacing: 14) {
            Text(exercise.localizedNote).font(.subheadline).foregroundStyle(HybrdStyle.muted)
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
              HStack {
                Text(L10n.text("Set \(setIndex + 1)")).foregroundStyle(HybrdStyle.muted)
                Spacer()
                Text(L10n.text("\(set.reps) reps"))
                Text(L10n.text("· \(set.targetRIR) RIR")).foregroundStyle(HybrdStyle.muted)
              }.font(.subheadline).monospacedDigit()
                .accessibilityElement(children: .combine)
            }
            Text(L10n.text("RIR = reps left in reserve.")).font(.caption).foregroundStyle(HybrdStyle.muted)
            if let previous = store.previousSets(for: exercise.name).first {
              Label(L10n.text("Last time: ") + units.weightText(previous.kilograms) + " × \(previous.reps)", systemImage: "clock.arrow.circlepath")
                .font(.caption).foregroundStyle(HybrdStyle.muted)
            }
          }.padding(.top, 12).padding(.bottom, 8)
        } label: {
          HStack(alignment: .top, spacing: 16) {
            Text(String(format: "%02d", index + 1))
              .font(.system(.title2, design: .rounded, weight: .medium))
              .foregroundStyle(HybrdStyle.terraText)
              .frame(minWidth: 30, alignment: .leading)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
              Text(exercise.localizedName).font(.headline).foregroundStyle(HybrdStyle.ink)
              Text(setSummary(exercise))
                .font(.subheadline).foregroundStyle(HybrdStyle.muted)
              HStack(spacing: 8) {
                HStack(spacing: 4) {
                  ForEach(exercise.sets) { _ in
                    Capsule().fill(HybrdStyle.terra).frame(width: 12, height: 4)
                  }
                }.accessibilityHidden(true)
                Text("·")
                Label(L10n.text("\(exercise.restSeconds)s rest"), systemImage: "timer")
              }.font(.caption).foregroundStyle(HybrdStyle.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
          }.padding(.vertical, 14)
        }
        .tint(HybrdStyle.muted)
        Divider().overlay(HybrdStyle.line)
      }
    }
  }

  private func setSummary(_ exercise: ExercisePrescription) -> String {
    let reps = Set(exercise.sets.map(\.reps))
    if reps.count == 1, let count = reps.first {
      return L10n.text("\(exercise.sets.count) sets × \(count) reps")
    }
    return L10n.text("\(exercise.sets.count) sets · varied reps")
  }
}
