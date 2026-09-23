import SwiftUI

/// A prominent, directly editable value with a persistent label and unit.
struct ProfileMetricField: View {
  var title: String
  @Binding var text: String
  var unit: String
  var tone: SessionBreakdown.Tone
  var placeholder = L10n.text("Not set")
  var accessibilityTitle: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.subheadline.weight(.medium)).foregroundStyle(SessionPalette.ink(tone))
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        TextField(title, text: $text, prompt: Text(placeholder)).labelsHidden()
          .font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
          .foregroundStyle(HybrdStyle.ink).accessibilityLabel((accessibilityTitle ?? title) + (unit.isEmpty ? "" : ", " + unit))
        if !unit.isEmpty { Text(unit).font(.subheadline).foregroundStyle(HybrdStyle.muted) }
      }
    }
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
