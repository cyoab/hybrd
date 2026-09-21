import SwiftUI

/// A scalable geometric rendering of the supplied wordmark; never a stretched screenshot.
struct HybrdWordmark: View {
  var body: some View {
    HStack(alignment: .bottom, spacing: 3) {
      GeometryReader { geometry in
        wordmark
          .stroke(HybrdStyle.ink, style: StrokeStyle(lineWidth: 8, lineCap: .butt, lineJoin: .round))
          .scaleEffect(x: geometry.size.width / 354, y: geometry.size.height / 116, anchor: .topLeading)
      }
      .frame(width: 91, height: 30)
      Circle().fill(HybrdStyle.terra).frame(width: 5, height: 5).padding(.bottom, 7)
    }
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("hybrd")
  }

  private var wordmark: Path {
    Path { path in
      path.move(to: CGPoint(x: 8, y: 4))
      path.addLine(to: CGPoint(x: 8, y: 86))
      path.move(to: CGPoint(x: 8, y: 58))
      path.addCurve(to: CGPoint(x: 64, y: 60), control1: CGPoint(x: 8, y: 23), control2: CGPoint(x: 64, y: 23))
      path.addLine(to: CGPoint(x: 64, y: 86))

      path.move(to: CGPoint(x: 78, y: 36))
      path.addCurve(to: CGPoint(x: 140, y: 65), control1: CGPoint(x: 93, y: 91), control2: CGPoint(x: 135, y: 102))
      path.move(to: CGPoint(x: 140, y: 35))
      path.addLine(to: CGPoint(x: 140, y: 88))
      path.addCurve(to: CGPoint(x: 114, y: 113), control1: CGPoint(x: 140, y: 109), control2: CGPoint(x: 129, y: 113))

      path.move(to: CGPoint(x: 160, y: 4))
      path.addLine(to: CGPoint(x: 160, y: 60))
      path.addEllipse(in: CGRect(x: 160, y: 34, width: 58, height: 52))

      path.move(to: CGPoint(x: 236, y: 86))
      path.addLine(to: CGPoint(x: 236, y: 61))
      path.addCurve(to: CGPoint(x: 280, y: 39), control1: CGPoint(x: 236, y: 32), control2: CGPoint(x: 259, y: 27))

      path.addEllipse(in: CGRect(x: 286, y: 34, width: 58, height: 52))
      path.move(to: CGPoint(x: 344, y: 4))
      path.addLine(to: CGPoint(x: 344, y: 86))
    }
  }
}
