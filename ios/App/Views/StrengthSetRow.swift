import SwiftUI

struct StrengthSetRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicType
  @Binding var loggedSet: LoggedSet
  var number: Int
  var previous: LoggedSet?
  var remove: () -> Void
  private var valid: Bool { loggedSet.reps > 0 && loggedSet.reps <= 100 && loggedSet.kilograms.isFinite && (0...1_000).contains(loggedSet.kilograms) && (loggedSet.rir.map { (0...10).contains($0) } ?? true) }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if dynamicType.isAccessibilitySize {
        HStack { Text("Set \(number)").font(.headline); Spacer(); completionToggle }
        VStack(spacing: 10) {
          LabeledContent("Weight · kg") { weightField }
          LabeledContent("Reps") { repsField }
          LabeledContent("Reps in reserve") { rirField }
        }
      } else {
        HStack(spacing: 7) {
          Text("\(number)").font(.subheadline.weight(.semibold)).frame(width: 22)
          weightField; repsField; rirField.frame(width: 48); completionToggle.frame(width: 44)
        }
      }
      if let previous {
        Text("Last time · \(previous.kilograms.formatted()) kg × \(previous.reps)" + (previous.rir.map { " · \($0) RIR" } ?? ""))
          .font(.caption2).foregroundStyle(HybrdStyle.muted).padding(.leading, dynamicType.isAccessibilitySize ? 0 : 29)
      }
    }
    .padding(10)
    .background(loggedSet.isComplete ? SessionPalette.wash(.violet) : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    .contextMenu { Button("Remove logged set", systemImage: "trash", role: .destructive, action: remove) }
    .accessibilityAction(named: Text("Remove set"), remove)
  }
  private var weightField: some View {
    TextField("0", value: $loggedSet.kilograms, format: .number.precision(.fractionLength(0...1)))
      .keyboardType(.decimalPad).accessibilityLabel("\(loggedSet.exerciseName), set \(number), kilograms")
      .multilineTextAlignment(.center).font(.body.monospacedDigit()).frame(maxWidth: .infinity, minHeight: 44)
      .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 9))
  }
  private var repsField: some View {
    TextField("Reps", value: $loggedSet.reps, format: .number).keyboardType(.numberPad)
      .accessibilityLabel("\(loggedSet.exerciseName), set \(number), reps")
      .multilineTextAlignment(.center).font(.body.monospacedDigit()).frame(maxWidth: .infinity, minHeight: 44)
      .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 9))
  }
  private var rirField: some View {
    Picker("Set \(number), reps in reserve", selection: $loggedSet.rir) {
      Text("—").tag(Int?.none)
      ForEach(0...10, id: \.self) { Text($0 == 10 ? "10+" : "\($0)").tag(Int?.some($0)) }
    }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, minHeight: 44)
      .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 9))
  }
  private var completionToggle: some View {
    Toggle(isOn: $loggedSet.isComplete) {
      Image(systemName: loggedSet.isComplete ? "checkmark.circle.fill" : "circle")
        .font(.title2).foregroundStyle(loggedSet.isComplete ? SessionPalette.ink(.violet) : HybrdStyle.muted)
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }.toggleStyle(.button).buttonStyle(.plain).disabled(!valid && !loggedSet.isComplete)
      .accessibilityLabel("\(loggedSet.exerciseName), set \(number) completed")
      .accessibilityValue(loggedSet.isComplete ? "Completed" : "Not completed")
  }
}
