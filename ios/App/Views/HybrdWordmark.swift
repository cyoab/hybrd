import SwiftUI

/// Uses the original lettering as an alpha mask, independent of its background or container.
struct HybrdWordmark: View {
  // Crop ends before the separate TM mark on the source sheet.
  private let scale: CGFloat = 92 / 565

  var body: some View {
    HStack(alignment: .bottom, spacing: 3) {
      HybrdStyle.ink
        .frame(width: 92, height: 224 * scale)
        .mask {
          artwork
            // Remove the sheet's faint paper texture while retaining antialiased edges.
            .grayscale(1).contrast(2).colorInvert().luminanceToAlpha()
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
