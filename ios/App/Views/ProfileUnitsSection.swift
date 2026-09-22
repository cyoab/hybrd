import SwiftUI

struct ProfileUnitsSection: View {
  @Bindable var editor: AthleteProfileEditor

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        Label("Weight", systemImage: "dumbbell").font(.headline).foregroundStyle(SessionPalette.ink(.violet))
        Picker("Weight unit", selection: Binding(get: { editor.units.weight }, set: { editor.setWeightUnit($0) })) {
          ForEach(TrainingWeightUnit.allCases) { unit in
            Text(unit.symbol).tag(unit).accessibilityLabel(unit.title)
          }
        }.pickerStyle(.segmented).labelsHidden().disabled(!editor.canChangeWeightUnit)
        Text("Lifting, body weight & strength PRs").font(.caption).foregroundStyle(HybrdStyle.muted)
        if !editor.canChangeWeightUnit { Text(editor.weightError).font(.caption).foregroundStyle(HybrdStyle.terraText) }
      }.padding(.vertical, 8).modifier(ProfileTintedRow(tone: .violet))
      VStack(alignment: .leading, spacing: 12) {
        Label("Endurance", systemImage: "figure.run").font(.headline).foregroundStyle(SessionPalette.ink(.terra))
        Picker("Distance unit", selection: Binding(get: { editor.units.distance }, set: { editor.setDistanceUnit($0) })) {
          ForEach(TrainingDistanceUnit.allCases) { unit in
            Text(unit == .kilometers ? "km" : "miles").tag(unit).accessibilityLabel(unit.title)
          }
        }.pickerStyle(.segmented).labelsHidden().disabled(editor.parsedWeeklyKilometers == nil)
        Text("Distance, pace & automatic run splits").font(.caption).foregroundStyle(HybrdStyle.muted)
        if editor.parsedWeeklyKilometers == nil { Text(editor.weeklyDistanceError).font(.caption).foregroundStyle(HybrdStyle.terraText) }
      }.padding(.vertical, 8).modifier(ProfileTintedRow(tone: .terra))
    } header: { Text("Units") } footer: {
      Text("Choose each independently. Save your profile to apply them across hybrd and send them to your Watch. Existing records keep their original measurements.")
    }
  }
}
