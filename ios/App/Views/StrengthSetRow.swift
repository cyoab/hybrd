import SwiftUI

struct StrengthSetRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicType
  @Binding var loggedSet: LoggedSet
  var number: Int
  var previous: LoggedSet?
  var remove: () -> Void

  private var valid: Bool { loggedSet.reps > 0 && loggedSet.reps <= 100 && loggedSet.kilograms.isFinite && (0...1_000).contains(loggedSet.kilograms) }

  var body: some View {
    Group {
      if dynamicType.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Set \(number)").font(.headline)
            Spacer()
            completionToggle
          }
          Text("Previous: " + previousText).font(.subheadline).foregroundStyle(HybrdStyle.muted)
          HStack {
            VStack { Text("KG").font(.caption); weightField }
            VStack { Text("REPS").font(.caption); repsField }
          }
        }.padding(12)
      } else {
        HStack(spacing: 8) {
          Text("\(number)").font(.subheadline.weight(.medium)).frame(width: 24)
          Text(previousText).font(.caption).foregroundStyle(HybrdStyle.muted).frame(width: 70)
          weightField
          repsField
          completionToggle.frame(width: 44)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
      }
    }
    .background(loggedSet.isComplete ? HybrdStyle.terraWash : Color.clear, in: RoundedRectangle(cornerRadius: 12))
    .contextMenu {
      Button("Remove logged set", systemImage: "trash", role: .destructive, action: remove)
    }
    .accessibilityAction(named: Text("Remove set"), remove)
  }

  private var previousText: String {
    guard let previous else { return "—" }
    return "\(previous.kilograms.formatted(.number.precision(.fractionLength(0...1)))) × \(previous.reps)"
  }

  private var weightField: some View {
    TextField("0", value: $loggedSet.kilograms, format: .number.precision(.fractionLength(0...1)))
      .keyboardType(.decimalPad)
      .accessibilityLabel("\(loggedSet.exerciseName), set \(number), kilograms")
      .multilineTextAlignment(.center)
      .font(.body.monospacedDigit())
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity)
      .background(HybrdStyle.field.opacity(loggedSet.isComplete ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 8))
  }

  private var repsField: some View {
    TextField("Reps", value: $loggedSet.reps, format: .number)
      .keyboardType(.numberPad)
      .accessibilityLabel("\(loggedSet.exerciseName), set \(number), reps")
      .multilineTextAlignment(.center)
      .font(.body.monospacedDigit())
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity)
      .background(HybrdStyle.field.opacity(loggedSet.isComplete ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 8))
  }

  private var completionToggle: some View {
    Toggle(isOn: $loggedSet.isComplete) {
      Image(systemName: "checkmark")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(loggedSet.isComplete ? Color.white : HybrdStyle.muted)
        .frame(width: 30, height: 30)
        .background(loggedSet.isComplete ? HybrdStyle.terraText : HybrdStyle.field, in: RoundedRectangle(cornerRadius: 8))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .toggleStyle(.button).buttonStyle(.plain)
    .disabled(!valid && !loggedSet.isComplete)
    .accessibilityLabel("\(loggedSet.exerciseName), set \(number) completed")
    .accessibilityValue(loggedSet.isComplete ? "Completed" : "Not completed")
  }
}
