import SwiftUI

struct GymSetupView: View {
  @Bindable var editor: AthleteProfileEditor
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var search = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 10) {
          Text(L10n.text("Your space to get stronger.")).font(.system(.title, design: .rounded, weight: .semibold))
          Text(L10n.text("Select the equipment you can use regularly. Bodyweight exercises are always included."))
            .font(.subheadline).foregroundStyle(HybrdStyle.muted)
          Button(L10n.text("Use bodyweight only"), systemImage: "figure.stand") {
            editor.details.equipment = []
            editor.details.gymConfigured = true
          }
          .buttonStyle(HybrdSecondaryButtonStyle())
        }
        ForEach(GymEquipment.categories, id: \.self) { category in
          let items = GymEquipment.allCases.filter {
            $0.category == category && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
          }
          if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              Text(category).font(.headline)
              LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 250 : 140))], spacing: 10) {
                ForEach(items) { equipment in
                  let selected = editor.details.equipment.contains(equipment)
                  Toggle(isOn: Binding(
                    get: { editor.details.equipment.contains(equipment) },
                    set: { enabled in
                      editor.details.gymConfigured = true
                      if enabled { editor.details.equipment.insert(equipment) }
                      else { editor.details.equipment.remove(equipment) }
                    })) {
                    GymEquipmentCard(equipment: equipment, selected: selected)
                  }
                  .toggleStyle(.button).buttonStyle(.plain).accessibilityLabel(equipment.title)
                }
              }
            }
          }
        }
        if !search.isEmpty && !GymEquipment.allCases.contains(where: { $0.title.localizedCaseInsensitiveContains(search) }) {
          ContentUnavailableView.search(text: search)
        }
      }
      .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
    .background(HybrdStyle.background)
    .searchable(text: $search, prompt: L10n.text("Find equipment"))
    .navigationTitle(L10n.text("Your gym")).navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      Text(editor.details.gymConfigured ? L10n.text("\(editor.details.equipment.count) equipment types · bodyweight included") : L10n.text("Choose your setup"))
        .font(.subheadline.weight(.medium)).padding().frame(maxWidth: .infinity).background(HybrdStyle.surface)
    }
  }
}
