import SwiftUI

struct StrengthBestEditorView: View {
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

  private var valid: Bool {
    !exerciseID.isEmpty && TrainingProfile.parseDecimal(weight, range: 0...1_000) != nil &&
      Int(reps).map { (1...100).contains($0) } == true
  }
  private var changed: Bool {
    loaded && (exerciseID != (record?.exerciseID ?? "") ||
      exerciseName != (record?.exerciseName ?? "") ||
      weight != (record?.kilograms.formatted(.number.grouping(.never)) ?? "") ||
      reps != (record.map { String($0.reps) } ?? ""))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          ProfileSectionHero(eyebrow: "Strength record", title: "Make it a milestone.",
            subtitle: "Choose your lift, then record the load and the reps you completed.",
            artwork: .strength, tone: .violet)
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
        Section {
          NavigationLink {
            StrengthExercisePicker { exercise in exerciseID = exercise.id; exerciseName = exercise.name }
          } label: { LabeledContent("Exercise", value: exerciseName.isEmpty ? "Choose" : exerciseName) }
          ProfileMetricField(title: "Weight", text: $weight, unit: "kg", tone: .violet)
            .keyboardType(.decimalPad).focused($focused).modifier(ProfileTintedRow(tone: .violet))
          ProfileMetricField(title: "Repetitions", text: $reps, unit: "reps", tone: .violet, placeholder: "e.g. 5")
            .keyboardType(.numberPad).focused($focused).modifier(ProfileTintedRow(tone: .violet))
        } footer: { Text("Use the total load for the movement. Keep your convention consistent for dumbbells and machines. Bodyweight-only sets can use 0 kg.") }
        if !valid && (!weight.isEmpty || !reps.isEmpty) {
          Section { Text("Choose an exercise, enter 0–1,000 kg, and 1–100 reps.").foregroundStyle(HybrdStyle.terraText) }
        }
      }
      .scrollContentBackground(.hidden).background(HybrdStyle.background)
      .navigationTitle(record == nil ? "Add strength PR" : "Edit strength PR")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { if changed { discard = true } else { dismiss() } }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            guard let kilograms = TrainingProfile.parseDecimal(weight, range: 0...1_000), let count = Int(reps), valid else { return }
            onSave(StrengthPersonalBest(id: record?.id ?? UUID(), exerciseID: exerciseID,
              exerciseName: exerciseName, kilograms: kilograms, reps: count, source: changed ? .manual : record?.source ?? .manual))
            dismiss()
          }.disabled(!valid)
        }
        ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
      }
      .interactiveDismissDisabled(changed)
      .confirmationDialog("Discard this record?", isPresented: $discard, titleVisibility: .visible) {
        Button("Discard", role: .destructive) { dismiss() }
        Button("Keep editing", role: .cancel) {}
      }
      .onAppear {
        guard !loaded else { return }
        if let record {
          exerciseID = record.exerciseID; exerciseName = record.exerciseName
          weight = record.kilograms.formatted(.number.grouping(.never)); reps = String(record.reps)
        }
        loaded = true
      }
    }
  }
}
