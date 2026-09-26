import SwiftUI

struct GymEquipmentCard: View {
  var equipment: GymEquipment
  var selected: Bool
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      EquipmentIllustration(equipment: equipment)
        .frame(height: typeSize.isAccessibilitySize ? 150 : 116)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? SessionPalette.ink(.violet) : HybrdStyle.muted)
            .background(HybrdStyle.surface, in: Circle())
            .accessibilityHidden(true)
        }
      Text(equipment.title)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 56 : 40, alignment: .topLeading)
    }
    .padding(14)
    .foregroundStyle(HybrdStyle.ink)
    .background(selected ? SessionPalette.wash(.violet) : HybrdStyle.surface,
      in: RoundedRectangle(cornerRadius: 22))
    .overlay(RoundedRectangle(cornerRadius: 22)
      .strokeBorder(selected ? SessionPalette.violet : HybrdStyle.line, lineWidth: selected ? 1.5 : 1))
    .contentShape(RoundedRectangle(cornerRadius: 22))
  }
}
