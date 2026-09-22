import SwiftUI

struct ProfileAppearanceSection: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding var appearance: AppAppearance

  var body: some View {
    Section {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          appearancePicker.pickerStyle(.menu)
        } else {
          appearancePicker.pickerStyle(.segmented).labelsHidden()
        }
      }
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
        Text(option.title).tag(option)
      }
    }
    .tint(HybrdStyle.ink)
  }
}
