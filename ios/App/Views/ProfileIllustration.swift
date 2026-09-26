import SwiftUI

/// Decorative artwork in the same shaded vector style as the gym inventory.
struct ProfileIllustration: View {
  enum Artwork { case identity, experience, heart, running, strength, rhythm }
  var artwork: Artwork

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width / 180, size.height / 140)
      var canvas = context
      canvas.translateBy(x: (size.width - 180 * scale) / 2, y: (size.height - 140 * scale) / 2)
      canvas.scaleBy(x: scale, y: scale)
      let painter = ProfileArtworkPainter(context: canvas)
      switch artwork {
      case .identity: painter.identity()
      case .experience: painter.experience()
      case .heart: painter.heart()
      case .running: painter.stopwatch()
      case .strength: painter.trophy()
      case .rhythm: painter.rhythm()
      }
    }
    .accessibilityHidden(true).allowsHitTesting(false)
  }
}

private struct ProfileArtworkPainter {
  var context: GraphicsContext
  private var violet: Color { SessionPalette.violet }
  private var terra: Color { HybrdStyle.terra }
  private var steel: Color { HybrdStyle.adaptive(light: 0x536278, dark: 0xB3C2D5) }

  func identity() {
    oval(30, 119, 119, 10, violet.opacity(0.16))
    rounded(23, 32, 120, 88, 14, violet.opacity(0.6))
    rounded(19, 25, 120, 88, 14, SessionPalette.wash(.violet))
    rounded(19, 25, 120, 21, 10, violet)
    oval(32, 58, 35, 35, SessionPalette.color(.terra).opacity(0.22))
    oval(43, 61, 14, 14, terra)
    rounded(36, 78, 27, 14, 7, terra)
    stroke([(80, 64), (122, 64)], steel, 5)
    stroke([(80, 77), (111, 77)], steel.opacity(0.5), 4)
    stroke([(80, 90), (100, 90)], steel.opacity(0.5), 4)
    rounded(130, 48, 22, 76, 5, SessionPalette.gold)
    for y in stride(from: CGFloat(57), through: 115, by: 10) {
      stroke([(134, y), (y == 77 || y == 107 ? 145 : 141, y)], SessionPalette.ink(.gold), 2)
    }
    oval(105, 94, 27, 27, SessionPalette.mint)
    stroke([(113, 108), (118, 113), (126, 103)], .white, 3)
  }

  func experience() {
    let track = Path(roundedRect: CGRect(x: 20, y: 27, width: 140, height: 88), cornerRadius: 42)
    context.stroke(track, with: .color(SessionPalette.wash(.terra)), lineWidth: 16)
    context.stroke(track, with: .color(terra.opacity(0.5)), lineWidth: 2)
    rounded(29, 38, 48, 47, 12, terra)
    stroke([(40, 68), (48, 63), (49, 50), (57, 58), (68, 62)], .white, 4)
    stroke([(49, 60), (57, 71), (67, 75)], .white, 4)
    oval(52, 43, 8, 8, .white)
    rounded(91, 73, 61, 45, 12, violet)
    stroke([(106, 97), (138, 97)], .white, 5)
    rounded(100, 85, 9, 24, 3, .white)
    rounded(135, 85, 9, 24, 3, .white)
    oval(98, 22, 16, 16, SessionPalette.mint)
    oval(57, 105, 10, 10, SessionPalette.gold)
  }

  func heart() {
    oval(25, 119, 134, 9, terra.opacity(0.12))
    var shape = Path()
    shape.move(to: CGPoint(x: 90, y: 105))
    shape.addCurve(to: CGPoint(x: 40, y: 41), control1: CGPoint(x: 34, y: 76), control2: CGPoint(x: 24, y: 59))
    shape.addCurve(to: CGPoint(x: 90, y: 39), control1: CGPoint(x: 54, y: 23), control2: CGPoint(x: 75, y: 24))
    shape.addCurve(to: CGPoint(x: 140, y: 41), control1: CGPoint(x: 105, y: 24), control2: CGPoint(x: 128, y: 23))
    shape.addCurve(to: CGPoint(x: 90, y: 105), control1: CGPoint(x: 162, y: 63), control2: CGPoint(x: 131, y: 83))
    context.fill(shape, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFAF80), terra]),
      startPoint: CGPoint(x: 50, y: 32), endPoint: CGPoint(x: 125, y: 105)))
    stroke([(47, 64), (65, 64), (74, 49), (85, 80), (98, 58), (106, 65), (132, 65)], .white, 4)
    for zone in HeartRateZone.allCases {
      rounded(32 + CGFloat(zone.rawValue - 1) * 24, 112, 19, 8, 4,
        SessionPalette.color(SessionBreakdown.tone(for: zone)))
    }
  }

  func stopwatch() {
    oval(31, 122, 112, 10, terra.opacity(0.14))
    rounded(77, 12, 31, 12, 4, steel)
    rounded(87, 21, 10, 11, 3, steel)
    stroke([(125, 36), (134, 28)], steel, 8)
    oval(45, 31, 96, 96, SessionPalette.ink(.terra))
    oval(41, 26, 96, 96, terra)
    oval(50, 35, 78, 78, SessionPalette.wash(.terra))
    for i in 0..<12 {
      let angle = Double(i) * .pi / 6
      stroke([(89 + 32 * sin(angle), 74 - 32 * cos(angle)),
        (89 + 28 * sin(angle), 74 - 28 * cos(angle))], steel.opacity(0.6), 2)
    }
    stroke([(89, 46), (89, 74), (106, 83)], steel, 4)
    oval(85, 70, 8, 8, terra)
    stroke([(26, 80), (12, 80)], SessionPalette.gold, 5)
    stroke([(27, 94), (18, 94)], SessionPalette.gold, 5)
    ribbon(x: 122, y: 96)
  }

  func trophy() {
    oval(33, 124, 119, 9, violet.opacity(0.15))
    let left = Path(roundedRect: CGRect(x: 28, y: 37, width: 38, height: 40), cornerRadius: 16)
    let right = Path(roundedRect: CGRect(x: 114, y: 37, width: 38, height: 40), cornerRadius: 16)
    context.stroke(left, with: .color(SessionPalette.gold), lineWidth: 8)
    context.stroke(right, with: .color(SessionPalette.gold), lineWidth: 8)
    rounded(82, 83, 17, 30, 5, SessionPalette.gold)
    rounded(60, 112, 62, 12, 5, SessionPalette.ink(.violet))
    rounded(56, 107, 62, 12, 5, violet)
    var cup = Path()
    cup.move(to: CGPoint(x: 51, y: 26)); cup.addLine(to: CGPoint(x: 130, y: 26))
    cup.addLine(to: CGPoint(x: 120, y: 72))
    cup.addQuadCurve(to: CGPoint(x: 90, y: 93), control: CGPoint(x: 116, y: 93))
    cup.addQuadCurve(to: CGPoint(x: 60, y: 72), control: CGPoint(x: 64, y: 93))
    cup.closeSubpath()
    context.fill(cup, with: .linearGradient(Gradient(colors: [violet, SessionPalette.ink(.violet)]),
      startPoint: CGPoint(x: 58, y: 27), endPoint: CGPoint(x: 125, y: 90)))
    stroke([(56, 27), (126, 27)], .white.opacity(0.5), 4)
    oval(75, 42, 29, 29, SessionPalette.gold)
    stroke([(80, 57), (99, 57)], .white, 3)
    rounded(78, 51, 4, 12, 1, .white)
    rounded(97, 51, 4, 12, 1, .white)
  }

  func rhythm() {
    oval(24, 121, 138, 10, SessionPalette.gold.opacity(0.15))
    rounded(28, 30, 123, 94, 14, SessionPalette.gold.opacity(0.7))
    rounded(22, 24, 123, 94, 14, SessionPalette.wash(.gold))
    rounded(22, 24, 123, 26, 11, SessionPalette.gold)
    for x: CGFloat in [49, 116] {
      stroke([(x, 18), (x, 33)], steel, 7)
      stroke([(x - 1, 18), (x - 1, 28)], .white.opacity(0.35), 2)
    }
    for row in 0..<3 {
      for column in 0..<4 {
        let x = CGFloat(38 + column * 23)
        let y = CGFloat(62 + row * 18)
        rounded(x, y, 12, 8, 3, steel.opacity(0.18))
      }
    }
    oval(38, 61, 12, 12, terra)
    rounded(61, 79, 12, 12, 3, violet)
    oval(84, 97, 12, 12, terra)
    oval(108, 79, 47, 47, SessionPalette.ink(.mint))
    oval(104, 75, 47, 47, SessionPalette.mint)
    oval(110, 81, 35, 35, SessionPalette.wash(.mint))
    stroke([(128, 87), (128, 99), (139, 104)], SessionPalette.ink(.mint), 3)
    oval(125, 96, 6, 6, SessionPalette.mint)
  }

  private func ribbon(x: CGFloat, y: CGFloat) {
    stroke([(x - 6, y + 6), (x - 10, y + 29)], SessionPalette.mint, 10)
    stroke([(x + 6, y + 6), (x + 10, y + 29)], SessionPalette.mint, 10)
    oval(x - 15, y - 15, 30, 30, SessionPalette.gold)
    oval(x - 9, y - 9, 18, 18, SessionPalette.wash(.gold))
    oval(x - 4, y - 4, 8, 8, SessionPalette.gold)
  }

  private func stroke(_ points: [(CGFloat, CGFloat)], _ color: Color, _ width: CGFloat) {
    guard let first = points.first else { return }
    var path = Path()
    path.move(to: CGPoint(x: first.0, y: first.1))
    for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
  }
  private func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
  }
  private func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ color: Color) {
    context.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius), with: .color(color))
  }
}
