import SwiftUI

struct MuscleFocusView: View {
  @Bindable var editor: AthleteProfileEditor
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 8) {
          Text(L10n.text("Where do you want to grow?"))
            .font(.system(.title, design: .rounded, weight: .semibold))
          Text(L10n.text("Choose the areas you’d like to prioritize. Leave all unselected for a balanced focus."))
            .font(.subheadline).foregroundStyle(HybrdStyle.muted)
        }
        HStack(spacing: 42) {
          diagram(posterior: false)
          diagram(posterior: true)
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(SessionPalette.wash(.violet), in: RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("Muscle focus diagram"))
        .accessibilityValue(selectionSummary)

        HStack {
          Text(L10n.text("Focus areas")).font(.headline)
          Spacer()
          Text(L10n.text("\(editor.details.focusMuscles.count) selected")).font(.caption).foregroundStyle(HybrdStyle.muted)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 145))], spacing: 12) {
          ForEach(MuscleGroup.allCases) { muscle in
            let selected = editor.details.focusMuscles.contains(muscle)
            Toggle(isOn: Binding(
              get: { editor.details.focusMuscles.contains(muscle) },
              set: { value in
                if value { editor.details.focusMuscles.insert(muscle) }
                else { editor.details.focusMuscles.remove(muscle) }
              })) {
              VStack(spacing: 10) {
                MuscleIllustration(selected: [muscle], posterior: muscle.isPosterior).frame(height: 94)
                HStack {
                  Text(muscle.title).font(.subheadline.weight(.semibold))
                  Spacer(minLength: 4)
                  Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? SessionPalette.violet : HybrdStyle.muted)
                }
              }
              .padding(16).frame(maxWidth: .infinity)
              .foregroundStyle(HybrdStyle.ink)
              .background(selected ? SessionPalette.wash(.violet) : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 22))
              .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(selected ? SessionPalette.violet : HybrdStyle.line))
              .contentShape(RoundedRectangle(cornerRadius: 22))
            }
            .toggleStyle(.button).buttonStyle(.plain).accessibilityLabel(muscle.title)
          }
        }
      }
      .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
    .background(HybrdStyle.background).navigationTitle(L10n.text("Muscle focus")).navigationBarTitleDisplayMode(.inline)
  }

  private var selectionSummary: String {
    let names = MuscleGroup.allCases.filter { editor.details.focusMuscles.contains($0) }.map(\.title)
    return names.isEmpty ? L10n.text("Balanced, no priority muscles") : names.joined(separator: ", ")
  }
  private func diagram(posterior: Bool) -> some View {
    VStack(spacing: 10) {
      MuscleIllustration(selected: editor.details.focusMuscles, posterior: posterior).frame(height: 200)
      Text(posterior ? L10n.text("BACK") : L10n.text("FRONT")).font(.caption2.weight(.medium)).tracking(1.2).foregroundStyle(HybrdStyle.muted)
    }
  }
}
