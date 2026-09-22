import SwiftUI

struct ProfileAppearanceSection: View {
  @Binding var appearance: AppAppearance

  var body: some View {
    Section {
      appearancePicker
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.vertical, 4)
        .listRowBackground(HybrdStyle.surface)
    } header: {
      Text("Appearance")
    } footer: {
      Text("System follows your device settings. Appearance changes are saved automatically.")
    }
  }

  private var appearancePicker: some View {
    Picker("Appearance", selection: $appearance) {
      ForEach(AppAppearance.allCases) { option in
        Label(option.title, systemImage: option.symbol)
          .labelStyle(.iconOnly)
          .accessibilityLabel(option.title)
          .help(option.title)
          .tag(option)
      }
    }
    .tint(HybrdStyle.ink)
  }
}
