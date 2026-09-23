import SwiftUI

struct OnboardingOption: View {
  var title: String
  var detail: String? = nil
  var symbol: String
  var tone: SessionBreakdown.Tone = .terra
  var selected: Bool
  var select: () -> Void

  var body: some View {
    Toggle(isOn: Binding(get: { selected }, set: { if $0 { select() } })) {
      HStack(spacing: 14) {
        Image(systemName: symbol).font(.title3.weight(.medium))
          .foregroundStyle(SessionPalette.ink(tone)).frame(width: 40, height: 44)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.headline)
          if let detail { Text(detail).font(.subheadline).foregroundStyle(HybrdStyle.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.title3).foregroundStyle(selected ? SessionPalette.ink(tone) : HybrdStyle.line)
          .accessibilityHidden(true)
      }
      .padding(16).foregroundStyle(HybrdStyle.ink)
      .background(selected ? SessionPalette.wash(tone) : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 22))
      .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(selected ? SessionPalette.color(tone) : HybrdStyle.line, lineWidth: selected ? 1.5 : 1))
      .contentShape(RoundedRectangle(cornerRadius: 22))
    }.toggleStyle(.button).buttonStyle(.plain)
  }
}
