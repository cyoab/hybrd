import SwiftUI

struct ProfileTintedRow: ViewModifier {
  var tone: SessionBreakdown.Tone

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 16).padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(SessionPalette.wash(tone), in: RoundedRectangle(cornerRadius: 22))
      .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
      .listRowBackground(Color.clear).listRowSeparator(.hidden)
  }
}
