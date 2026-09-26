import SwiftUI

struct StrengthSetRow: View {
  @Environment(\.trainingUnits) private var units
  @Environment(\.dynamicTypeSize) private var dynamicType
  @Binding var loggedSet: LoggedSet
  var number: Int
  var previous: LoggedSet?
  var prescription: SetPrescription? = nil
  var remove: () -> Void
  private var valid: Bool { loggedSet.reps > 0 && loggedSet.reps <= 100 && loggedSet.kilograms.isFinite && (0...1_000).contains(loggedSet.kilograms) && (loggedSet.measuredRIR.map { $0.isFinite && (0...10).contains($0) } ?? true) }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if let targets = prescription?.targets {
        Text(targets.summary(units: units)).font(.caption).foregroundStyle(HybrdStyle.muted)
        if let note = targets.notes { Text(note).font(.caption2).foregroundStyle(HybrdStyle.muted) }
      }
      Picker(L10n.text("Load type"), selection: Binding(get: { loggedSet.loadConvention ?? .external }, set: { loggedSet.loadConvention = $0; if $0 == .bodyweight { loggedSet.kilograms = 0 } })) {
        ForEach(LoggedSet.LoadConvention.allCases, id: \.self) { Text($0.title).tag($0) }
      }.pickerStyle(.menu).font(.caption)

      if dynamicType.isAccessibilitySize {
        HStack { Text(L10n.text("Set \(number)")).font(.headline); Spacer(); completionToggle }
        VStack(spacing: 10) {
          LabeledContent(L10n.text("Weight · ") + units.weight.symbol) { weightField }
          LabeledContent(L10n.text("Reps")) { repsField }
          LabeledContent(L10n.text("Reps in reserve")) { rirField }
        }
      } else {
        HStack(spacing: 7) {
          Text("\(number)").font(.subheadline.weight(.semibold)).frame(width: 22)
          weightField; repsField; rirField.frame(width: 48); completionToggle.frame(width: 44)
        }
      }
      if let previous {
        Text(L10n.text("Last time · ") + units.weightText(previous.kilograms) + " × \(previous.reps)" + (previous.measuredRIR.map { " · " + $0.formatted() + " RIR" } ?? ""))
          .font(.caption2).foregroundStyle(HybrdStyle.muted).padding(.leading, dynamicType.isAccessibilitySize ? 0 : 29)
      }
    }
    .padding(10)
    .background(loggedSet.isComplete ? SessionPalette.wash(.violet) : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    .contextMenu { Button(L10n.text("Remove logged set"), systemImage: "trash", role: .destructive, action: remove) }
    .accessibilityAction(named: Text(L10n.text("Remove set")), remove)
  }
  private var weightField: some View {
    TextField("0", value: Binding(get: { units.weight.value(fromKilograms: loggedSet.kilograms) }, set: { loggedSet.kilograms = units.weight.kilograms(from: $0) }), format: .number.precision(.fractionLength(0...1)))
      .disabled(loggedSet.loadConvention == .bodyweight)
      .keyboardType(.decimalPad).accessibilityLabel(L10n.text("\(loggedSet.localizedExerciseName), set \(number), \(units.weight.title.lowercased())"))
      .multilineTextAlignment(.center).font(.body.monospacedDigit()).frame(maxWidth: .infinity, minHeight: 44)
      .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 9))
  }
  private var repsField: some View {
    TextField(L10n.text("Reps"), value: $loggedSet.reps, format: .number).keyboardType(.numberPad)
      .accessibilityLabel(L10n.text("\(loggedSet.localizedExerciseName), set \(number), reps"))
      .multilineTextAlignment(.center).font(.body.monospacedDigit()).frame(maxWidth: .infinity, minHeight: 44)
      .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 9))
  }
  private var rirField: some View {
    Picker(L10n.text("Set \(number), reps in reserve"), selection: Binding(get: { loggedSet.measuredRIR }, set: { loggedSet.fractionalRIR = $0; loggedSet.rir = nil })) {
      Text("—").tag(Double?.none)
      ForEach(0...20, id: \.self) { value in Text((Double(value) / 2).formatted()).tag(Double?.some(Double(value) / 2)) }
    }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, minHeight: 44)
      .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 9))
  }
  private var completionToggle: some View {
    Toggle(isOn: $loggedSet.isComplete) {
      Image(systemName: loggedSet.isComplete ? "checkmark.circle.fill" : "circle")
        .font(.title2).foregroundStyle(loggedSet.isComplete ? SessionPalette.ink(.violet) : HybrdStyle.muted)
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }.toggleStyle(.button).buttonStyle(.plain).disabled(!valid && !loggedSet.isComplete)
      .accessibilityLabel(L10n.text("\(loggedSet.localizedExerciseName), set \(number) completed"))
      .accessibilityValue(loggedSet.isComplete ? L10n.text("Completed") : L10n.text("Not completed"))
  }
}
