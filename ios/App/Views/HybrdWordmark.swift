import SwiftUI

/// Displays the original supplied artwork without modifying its source pixels.
struct HybrdWordmark: View {
  @Environment(\.colorScheme) private var colorScheme
  private let scale: CGFloat = 92 / 572

  var body: some View {
    HStack(alignment: .bottom, spacing: 3) {
      Group {
        if colorScheme == .dark {
          artwork.colorInvert().blendMode(.screen)
        } else {
          artwork.blendMode(.multiply)
        }
      }
      Circle().fill(HybrdStyle.terra).frame(width: 5, height: 5).padding(.bottom, 9)
    }
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("hybrd")
  }

  private var artwork: some View {
    GeometryReader { _ in
      Image("BrandSheet")
        .resizable()
        .interpolation(.high)
        .frame(width: 1448 * scale, height: 1086 * scale)
        .offset(x: -132 * scale, y: -270 * scale)
    }
    .frame(width: 92, height: 224 * scale)
    .clipped()
  }
}
