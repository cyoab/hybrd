import SwiftUI

struct HealthImportReviewView: View {
  @Bindable var editor: AthleteProfileEditor
  var values: HealthProfileImport
  @Environment(\.dismiss) private var dismiss
  @State private var useBirth = false
  @State private var useWeight = false
  @State private var useHeight = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Choose what to fill in. Existing entries are kept unless you select a replacement.")
            .font(.subheadline)
          if let birth = values.birthDate {
            Toggle(isOn: $useBirth) {
              LabeledContent("Date of birth", value: birth.formatted(date: .abbreviated, time: .omitted))
            }
          }
          if let weight = values.weight {
            Toggle(isOn: $useWeight) { measurement("Weight", weight, unit: editor.units.weight.symbol, displayedValue: editor.units.weight.value(fromKilograms: weight.value)) }
          }
          if let height = values.height {
            Toggle(isOn: $useHeight) { measurement("Height", height, unit: "cm") }
          }
        } header: { Text("Available from Apple Health") } footer: {
          Text("Missing fields may not be stored in Health or may not be shared. You can edit imported values before saving your profile.")
        }
      }
      .navigationTitle("Review Health import").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            if useBirth, let birth = values.birthDate { editor.details.birthDate = birth }
            if useWeight, let weight = values.weight { editor.importWeight(kilograms: weight.value) }
            if useHeight, let height = values.height { editor.height = height.value.formatted(.number.grouping(.never).precision(.fractionLength(0...1))) }
            editor.details.lastHealthImport = Date()
            dismiss()
          }.disabled(!useBirth && !useWeight && !useHeight)
        }
      }
      .onAppear {
        useBirth = values.birthDate != nil && editor.details.birthDate == nil
        useWeight = values.weight != nil && editor.weight.isEmpty
        useHeight = values.height != nil && editor.height.isEmpty
      }
    }
  }

  private func measurement(_ title: String, _ value: HealthMeasurement, unit: String, displayedValue: Double? = nil) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("\(title) · \((displayedValue ?? value.value).formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
      Text("Measured \(value.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
    }
  }
}
