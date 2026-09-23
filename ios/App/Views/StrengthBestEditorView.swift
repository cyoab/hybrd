import SwiftUI

struct StrengthBestEditorView: View {
  @Environment(\.trainingUnits) private var units
  var record: StrengthPersonalBest?
  var onSave: (StrengthPersonalBest) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var exerciseID = ""
  @State private var exerciseName = ""
  @State private var weight = ""
  @State private var reps = ""
  @State private var loaded = false
  @State private var discard = false
  @FocusState private var focused: Bool

  private var initialWeight: String { record.map { units.weightInput($0.kilograms) } ?? "" }
  private var parsedKilograms: Double? {
    if let record, weight == initialWeight { return record.kilograms }
    return units.weight.parse(weight, kilograms: 0...1_000)
  }
  private var valid: Bool {
    !exerciseID.isEmpty && parsedKilograms != nil &&
      Int(reps).map { (1...100).contains($0) } == true
  }
  private var changed: Bool {
    loaded && (exerciseID != (record?.exerciseID ?? "") ||
      exerciseName != (record?.exerciseName ?? "") ||
      weight != initialWeight ||
      reps != (record.map { String($0.reps) } ?? ""))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          ProfileSectionHero(eyebrow: L10n.text("Strength record"), title: L10n.text("Make it a milestone."),
            subtitle: L10n.text("Choose your lift, then record the load and the reps you completed."),
            artwork: .strength, tone: .violet)
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
        Section {
          NavigationLink {
            StrengthExercisePicker { exercise in exerciseID = exercise.id; exerciseName = exercise.name }
          } label: { LabeledContent(L10n.text("Exercise"), value: exerciseName.isEmpty ? L10n.text("Choose") : exerciseName) }
          ProfileMetricField(title: L10n.text("Weight"), text: $weight, unit: units.weight.symbol, tone: .violet)
            .keyboardType(.decimalPad).focused($focused).modifier(ProfileTintedRow(tone: .violet))
          ProfileMetricField(title: L10n.text("Repetitions"), text: $reps, unit: L10n.text("reps"), tone: .violet, placeholder: L10n.text("e.g. 5"))
            .keyboardType(.numberPad).focused($focused).modifier(ProfileTintedRow(tone: .violet))
        } footer: { Text(L10n.text("Use the total load for the movement. Keep your convention consistent for dumbbells and machines. Bodyweight-only sets can use 0 \(units.weight.symbol).")) }
        if !valid && (!weight.isEmpty || !reps.isEmpty) {
          Section { Text(L10n.text("Choose an exercise, enter 0–\(units.weightText(1_000)), and 1–100 reps.")).foregroundStyle(HybrdStyle.terraText) }
        }
      }
      .scrollContentBackground(.hidden).background(HybrdStyle.background)
      .navigationTitle(record == nil ? L10n.text("Add strength PR") : L10n.text("Edit strength PR"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Cancel")) { if changed { discard = true } else { dismiss() } }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Done")) {
            guard let kilograms = parsedKilograms, let count = Int(reps), valid else { return }
            onSave(StrengthPersonalBest(id: record?.id ?? UUID(), exerciseID: exerciseID,
              exerciseName: exerciseName, kilograms: kilograms, reps: count, source: changed ? .manual : record?.source ?? .manual))
            dismiss()
          }.disabled(!valid)
        }
        ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(L10n.text("Done")) { focused = false } }
      }
      .interactiveDismissDisabled(changed)
      .confirmationDialog(L10n.text("Discard this record?"), isPresented: $discard, titleVisibility: .visible) {
        Button(L10n.text("Discard"), role: .destructive) { dismiss() }
        Button(L10n.text("Keep editing"), role: .cancel) {}
      }
      .onAppear {
        guard !loaded else { return }
        if let record {
          exerciseID = record.exerciseID; exerciseName = record.exerciseName
          weight = initialWeight; reps = String(record.reps)
        }
        loaded = true
      }
    }
  }
}
