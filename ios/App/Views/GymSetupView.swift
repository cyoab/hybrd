import SwiftUI

struct GymSetupView: View {
  @Bindable var editor: AthleteProfileEditor
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var search = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 10) {
          Text("Your space to get stronger.").font(.system(.title, design: .rounded, weight: .semibold))
          Text("Select the equipment you can use regularly. Bodyweight exercises are always included.")
            .font(.subheadline).foregroundStyle(HybrdStyle.muted)
          Button("Use bodyweight only", systemImage: "figure.stand") {
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
                    VStack(alignment: .leading, spacing: 16) {
                      HStack {
                        Image(systemName: equipment.symbol).font(.title2)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.body)
                      }
                      .foregroundStyle(SessionPalette.ink(.violet))
                      Text(equipment.title).font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                    }
                    .padding(16).foregroundStyle(HybrdStyle.ink)
                    .background(selected ? SessionPalette.wash(.violet) : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? SessionPalette.violet : HybrdStyle.line))
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
    .searchable(text: $search, prompt: "Find equipment")
    .navigationTitle("Your gym").navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      Text(editor.details.gymConfigured ? "\(editor.details.equipment.count) equipment types · bodyweight included" : "Choose your setup")
        .font(.subheadline.weight(.medium)).padding().frame(maxWidth: .infinity).background(HybrdStyle.surface)
    }
  }
}
