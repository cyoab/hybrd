import SwiftUI

/// Original vector miniatures, drawn in a shared 200 × 144 coordinate space.
struct EquipmentIllustration: View {
  var equipment: GymEquipment

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width / 200, size.height / 144)
      var drawing = context
      drawing.translateBy(x: (size.width - 200 * scale) / 2, y: (size.height - 144 * scale) / 2)
      drawing.scaleBy(x: scale, y: scale)
      EquipmentArtwork(context: drawing, tone: tone).draw(equipment)
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private var tone: SessionBreakdown.Tone {
    switch equipment {
    case .dumbbells, .barbell, .kettlebell, .ezBar, .plates: .terra
    case .bench, .rack, .pullUpBar, .cableMachine: .sky
    case .bands, .medicineBall, .stabilityBall, .foamRoll: .mint
    default: .violet
    }
  }
}

private struct EquipmentArtwork {
  var context: GraphicsContext
  var tone: SessionBreakdown.Tone
  private var accent: Color { SessionPalette.color(tone) }
  private var deep: Color { SessionPalette.ink(tone) }
  private var steel: Color { HybrdStyle.adaptive(light: 0x657080, dark: 0xB3BECE) }
  private var frame: Color { HybrdStyle.adaptive(light: 0x333D50, dark: 0x728199) }
  private var highlight: Color { HybrdStyle.adaptive(light: 0xB7C3D4, dark: 0xD4DEEB) }

  func draw(_ equipment: GymEquipment) {
    ellipse(46, 23, 110, 110, SessionPalette.wash(tone))
    ellipse(31, 121, 138, 12, frame.opacity(0.10))
    switch equipment {
    case .dumbbells:
      var rear = context
      rear.translateBy(x: 28, y: 47)
      rear.rotate(by: .degrees(-17))
      EquipmentArtwork(context: rear, tone: tone).dumbbell()
      var front = context
      front.translateBy(x: 65, y: 90)
      front.rotate(by: .degrees(-17))
      EquipmentArtwork(context: front, tone: tone).dumbbell()
    case .barbell: barbell(curled: false)
    case .ezBar: barbell(curled: true)
    case .kettlebell: kettlebell()
    case .plates:
      plate(x: 121, y: 75, width: 43, height: 75)
      plate(x: 97, y: 87, width: 42, height: 76)
      plate(x: 72, y: 98, width: 41, height: 62)
    case .bench: bench()
    case .rack: rack(smith: false)
    case .smithMachine: rack(smith: true)
    case .pullUpBar: pullUpStation()
    case .cableMachine: cableStation()
    case .legPress: legPress()
    case .legExtension: legMachine(prone: false)
    case .legCurl: legMachine(prone: true)
    case .chestPress: chestPress()
    case .latPulldown: latPulldown()
    case .seatedRow: seatedRow()
    case .bands: bands()
    case .medicineBall: ball(stability: false)
    case .stabilityBall: ball(stability: true)
    case .foamRoll: foamRoller()
    }
  }

  // Filled, beveled weight heads with a metal grip.
  private func dumbbell() {
    rod([(4, 5), (82, 5)], width: 8)
    for x: CGFloat in [12, 62] {
      rounded(x + 4, -17, 19, 43, radius: 5, color: deep)
      rounded(x, -20, 19, 43, radius: 5, color: accent)
      line([(x + 4, -13), (x + 4, 13)], color: .white.opacity(0.4), width: 2)
    }
    for x in stride(from: 36, through: 51, by: 4) {
      line([(CGFloat(x), 2), (CGFloat(x - 2), 8)], color: frame.opacity(0.5), width: 1)
    }
  }

  private func barbell(curled: Bool) {
    let points: [(CGFloat, CGFloat)] = curled ?
      [(22, 95), (60, 78), (75, 88), (91, 64), (107, 76), (122, 55), (176, 34)] :
      [(22, 97), (178, 47)]
    rod(points, width: 7)
    plate(x: 144, y: 53, width: 23, height: curled ? 44 : 62)
    plate(x: 153, y: 49, width: 17, height: curled ? 36 : 50)
    // The grip is in front of the inner face of the far plate.
    rod(curled ? [(56, 80), (75, 88), (91, 64), (107, 76), (122, 55), (139, 49)] :
      [(54, 87), (137, 60)], width: 7)
    plate(x: 51, y: 88, width: 25, height: curled ? 47 : 66)
    plate(x: 39, y: 92, width: 18, height: curled ? 36 : 52)
    rod([(22, 97), (31, 94)], width: 6)
  }

  private func kettlebell() {
    let handle = Path(roundedRect: CGRect(x: 73, y: 27, width: 54, height: 50), cornerRadius: 18)
    context.stroke(handle, with: .color(deep), style: StrokeStyle(lineWidth: 12, lineCap: .round))
    context.stroke(handle, with: .color(accent), style: StrokeStyle(lineWidth: 6, lineCap: .round))
    gradientEllipse(65, 60, 72, 67, colors: [accent, deep])
    ellipse(74, 67, 21, 35, .white.opacity(0.22))
    rounded(85, 119, 39, 6, radius: 3, color: deep)
    ellipse(97, 88, 21, 21, deep.opacity(0.32))
    line([(101, 94), (113, 94)], color: .white.opacity(0.55), width: 2)
  }

  private func bench() {
    rod([(64, 81), (51, 117), (31, 121)], width: 7)
    rod([(117, 94), (135, 121), (161, 115)], width: 7)
    rod([(43, 116), (135, 121)], width: 6)
    rod([(71, 70), (111, 106)], width: 5)
    pad([(53, 34), (81, 25), (110, 84), (82, 95)])
    pad([(89, 92), (114, 81), (143, 93), (117, 107)])
    ellipse(95, 96, 7, 7, HybrdStyle.terra)
    line([(60, 36), (81, 82)], color: .white.opacity(0.32), width: 3)
  }

  private func rack(smith: Bool) {
    rod([(53, 37), (53, 119), (35, 125)], width: 7)
    rod([(126, 23), (126, 104), (112, 113)], width: 7)
    rod([(151, 34), (151, 117), (174, 123)], width: 7)
    rod([(77, 49), (77, 129), (99, 132)], width: 7)
    rod([(53, 37), (126, 23), (151, 34), (77, 49), (53, 37)], width: 6)
    rod([(77, 129), (151, 117)], width: 6)
    if smith {
      rod([(88, 49), (88, 122)], width: 3)
      rod([(141, 39), (141, 111)], width: 3)
      rounded(82, 66, 12, 15, radius: 3, color: accent)
      rounded(135, 54, 12, 15, radius: 3, color: accent)
    } else {
      for y: CGFloat in [62, 76, 90, 104] {
        ellipse(74, y, 3, 3, highlight)
        ellipse(148, y - 13, 3, 3, highlight)
      }
      line([(76, 85), (86, 84), (86, 79)], color: accent, width: 4)
      line([(150, 72), (160, 71), (160, 66)], color: accent, width: 4)
    }
    rod([(58, 79), (164, 60)], width: 5)
    plate(x: 144, y: 64, width: 15, height: 33)
    rod([(83, 74), (137, 65)], width: 5)
    plate(x: 74, y: 77, width: 16, height: 35)
  }

  private func pullUpStation() {
    rod([(52, 121), (65, 37), (136, 24), (149, 110)], width: 7)
    rod([(36, 128), (72, 121), (85, 128)], width: 7)
    rod([(128, 118), (162, 111), (176, 119)], width: 7)
    rod([(65, 94), (147, 78)], width: 5)
    rod([(58, 33), (50, 25), (142, 9), (154, 18)], width: 6)
    line([(50, 25), (71, 21)], color: accent, width: 8)
    line([(126, 12), (142, 9), (153, 18)], color: accent, width: 8)
    line([(65, 37), (78, 52)], color: accent, width: 4)
  }

  private func cableStation() {
    stack(x: 44, y: 60, height: 53)
    stack(x: 132, y: 44, height: 54)
    rod([(38, 122), (42, 32), (134, 16), (159, 30), (156, 111)], width: 6)
    rod([(42, 32), (67, 46), (159, 30)], width: 6)
    rod([(67, 46), (66, 126)], width: 6)
    rod([(29, 122), (69, 129), (167, 113)], width: 6)
    line([(51, 43), (87, 74), (75, 95)], color: steel, width: 2)
    line([(143, 34), (111, 64), (120, 87)], color: steel, width: 2)
    pulley(51, 43); pulley(143, 34)
    line([(75, 94), (65, 105), (83, 109), (75, 94)], color: accent, width: 4)
    line([(120, 87), (111, 98), (129, 102), (120, 87)], color: accent, width: 4)
  }

  private func legPress() {
    rod([(38, 121), (164, 112)], width: 7)
    rod([(68, 118), (130, 36)], width: 6)
    rod([(89, 120), (151, 41)], width: 6)
    rod([(147, 49), (163, 112)], width: 6)
    pad([(118, 26), (149, 29), (165, 53), (133, 52)])
    rod([(120, 66), (147, 71)], width: 6)
    plate(x: 148, y: 75, width: 25, height: 35)
    pad([(43, 79), (62, 74), (82, 99), (62, 106)])
    pad([(62, 108), (83, 99), (103, 108), (81, 119)])
    line([(47, 110), (42, 99)], color: frame, width: 5)
    for offset: CGFloat in [0, 7, 14] {
      line([(130 + offset, 33), (138 + offset, 46)], color: .white.opacity(0.35), width: 2)
    }
  }

  private func legMachine(prone: Bool) {
    stack(x: 141, y: 46, height: 60)
    rod([(151, 43), (153, 116), (172, 119)], width: 6)
    rod([(35, 122), (61, 113), (151, 116)], width: 6)
    if prone {
      rod([(57, 118), (65, 76)], width: 6)
      rod([(124, 117), (118, 82)], width: 6)
      pad([(35, 72), (64, 59), (103, 69), (74, 84)])
      pad([(74, 84), (104, 70), (132, 85), (103, 99)])
      rod([(125, 89), (139, 76), (129, 59)], width: 5)
      roller(from: (115, 63), to: (142, 55))
      rod([(40, 92), (32, 88), (34, 76)], width: 4)
    } else {
      rod([(61, 114), (65, 71)], width: 6)
      pad([(43, 41), (66, 35), (78, 79), (55, 86)])
      pad([(58, 88), (84, 77), (113, 91), (85, 104)])
      rod([(103, 94), (117, 114), (143, 105)], width: 6)
      roller(from: (121, 115), to: (148, 106))
      ellipse(100, 88, 9, 9, accent)
    }
  }

  private func chestPress() {
    stack(x: 124, y: 52, height: 55)
    rod([(49, 119), (143, 111)], width: 7)
    rod([(75, 118), (72, 71)], width: 6)
    rod([(135, 108), (133, 26)], width: 6)
    pad([(70, 44), (88, 39), (94, 83), (75, 88)])
    pad([(57, 93), (83, 82), (103, 92), (77, 103)])
    rod([(132, 32), (110, 20), (89, 38), (103, 65)], width: 5)
    rod([(111, 25), (57, 40), (47, 66)], width: 5)
    line([(43, 65), (52, 73)], color: accent, width: 7)
    line([(101, 64), (109, 72)], color: accent, width: 7)
    ellipse(126, 25, 10, 10, accent)
  }

  private func latPulldown() {
    stack(x: 122, y: 53, height: 58)
    rod([(132, 117), (130, 22), (93, 13), (74, 26)], width: 6)
    rod([(43, 125), (139, 117), (161, 124)], width: 6)
    rod([(68, 122), (72, 86)], width: 6)
    line([(78, 25), (77, 45)], color: steel, width: 2)
    pulley(79, 25)
    rod([(38, 54), (55, 42), (96, 45), (113, 57)], width: 4)
    line([(38, 54), (51, 45)], color: accent, width: 6)
    line([(99, 48), (113, 57)], color: accent, width: 6)
    pad([(53, 89), (78, 80), (98, 91), (72, 101)])
    roller(from: (53, 77), to: (83, 71))
  }

  private func seatedRow() {
    stack(x: 132, y: 43, height: 64)
    rod([(143, 41), (149, 116)], width: 7)
    rod([(32, 124), (151, 116), (170, 122)], width: 7)
    rod([(53, 120), (55, 95)], width: 6)
    pad([(33, 92), (58, 82), (84, 94), (57, 105)])
    polygon([(96, 103), (103, 85), (117, 86), (113, 105)], frame)
    line([(141, 65), (95, 76), (72, 70)], color: steel, width: 2)
    pulley(140, 65)
    line([(70, 65), (81, 73), (70, 81)], color: accent, width: 5)
    line([(101, 90), (110, 91)], color: highlight, width: 2)
  }

  private func bands() {
    var rear = context
    rear.translateBy(x: 67, y: 38)
    rear.rotate(by: .degrees(22))
    let rearPath = Path(roundedRect: CGRect(x: 0, y: 0, width: 43, height: 87), cornerRadius: 21)
    rear.stroke(rearPath, with: .color(SessionPalette.sky), style: StrokeStyle(lineWidth: 13))
    rear.stroke(rearPath, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 3))
    var front = context
    front.translateBy(x: 113, y: 38)
    front.rotate(by: .degrees(-22))
    let frontPath = Path(roundedRect: CGRect(x: 0, y: 0, width: 39, height: 87), cornerRadius: 19)
    front.stroke(frontPath, with: .color(deep), style: StrokeStyle(lineWidth: 15))
    front.stroke(frontPath, with: .color(accent), style: StrokeStyle(lineWidth: 9))
    rounded(65, 111, 29, 10, radius: 4, color: frame)
  }

  private func ball(stability: Bool) {
    let r: CGFloat = stability ? 49 : 36
    let center = CGPoint(x: 100, y: 126 - r)
    let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
    let shape = Path(ellipseIn: rect)
    context.fill(shape, with: .radialGradient(Gradient(colors: [accent, deep]),
      center: CGPoint(x: center.x - 18, y: center.y - 24), startRadius: 3, endRadius: 2 * r))
    var clipped = context
    clipped.clip(to: shape)
    if stability {
      for offset in stride(from: -32, through: 32, by: 13) {
        let curve = Path(ellipseIn: CGRect(x: 45, y: center.y + CGFloat(offset) - 19, width: 110, height: 38))
        clipped.stroke(curve, with: .color(deep.opacity(0.32)), lineWidth: 1.5)
      }
    } else {
      var seam = Path()
      seam.move(to: CGPoint(x: 96, y: 53))
      seam.addCurve(to: CGPoint(x: 98, y: 128), control1: CGPoint(x: 122, y: 74), control2: CGPoint(x: 71, y: 109))
      clipped.stroke(seam, with: .color(frame.opacity(0.65)), lineWidth: 5)
      clipped.stroke(Path(ellipseIn: CGRect(x: 50, y: 81, width: 100, height: 31)),
        with: .color(frame.opacity(0.65)), lineWidth: 5)
    }
    ellipse(center.x - r * 0.55, center.y - r * 0.64, r * 0.45, r * 0.30, .white.opacity(0.25))
  }

  private func foamRoller() {
    polygon([(54, 53), (135, 67), (135, 121), (54, 107)], deep)
    let side = Path(CGRect(x: 54, y: 65, width: 82, height: 42))
    context.fill(side, with: .linearGradient(Gradient(colors: [accent, deep]),
      startPoint: CGPoint(x: 65, y: 61), endPoint: CGPoint(x: 82, y: 115)))
    ellipse(34, 52, 42, 55, accent)
    for x in stride(from: 64, through: 124, by: 12) {
      line([(CGFloat(x), 59 + CGFloat(x - 64) * 0.17), (CGFloat(x), 109 + CGFloat(x - 64) * 0.17)],
        color: deep.opacity(0.45), width: 3)
    }
    gradientEllipse(112, 66, 45, 56, colors: [accent, deep])
    ellipse(121, 76, 27, 36, frame)
    ellipse(128, 83, 14, 23, deep)
    line([(50, 63), (50, 87)], color: .white.opacity(0.3), width: 4)
  }

  // Common construction details keep the miniatures visually consistent.
  private func plate(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    ellipse(x - width / 2 + 5, y - height / 2 + 2, width, height, deep)
    gradientEllipse(x - width / 2, y - height / 2, width, height, colors: [accent, deep])
    let inset = CGRect(x: x - width * 0.32, y: y - height * 0.37, width: width * 0.64, height: height * 0.74)
    context.stroke(Path(ellipseIn: inset), with: .color(.white.opacity(0.26)), lineWidth: 1.5)
    ellipse(x - 3, y - 5, 6, 10, frame)
    ellipse(x - 1.5, y - 3, 3, 6, highlight)
  }

  private func stack(x: CGFloat, y: CGFloat, height: CGFloat) {
    rounded(x - 10, y, 25, height, radius: 4, color: frame)
    for level in stride(from: CGFloat(7), to: height - 4, by: 7) {
      line([(x - 6, y + level), (x + 11, y + level)], color: steel, width: 2)
    }
    line([(x - 5, y - 6), (x - 5, y + height + 6)], color: highlight, width: 2)
    line([(x + 10, y - 6), (x + 10, y + height + 6)], color: highlight, width: 2)
    ellipse(x + 4, y + height * 0.45, 6, 5, HybrdStyle.terra)
  }

  private func roller(from start: (CGFloat, CGFloat), to end: (CGFloat, CGFloat)) {
    line([start, end], color: deep, width: 17)
    line([(start.0, start.1 - 3), (end.0, end.1 - 3)], color: accent, width: 11)
    ellipse(start.0 - 7, start.1 - 7, 12, 15, accent)
    ellipse(start.0 - 3, start.1 - 3, 4, 6, deep)
  }

  private func pulley(_ x: CGFloat, _ y: CGFloat) {
    ellipse(x - 5, y - 5, 10, 10, accent)
    ellipse(x - 2, y - 2, 4, 4, frame)
  }

  private func pad(_ points: [(CGFloat, CGFloat)]) {
    polygon(points.map { ($0.0, $0.1 + 6) }, deep)
    let path = polygonPath(points)
    context.fill(path, with: .linearGradient(Gradient(colors: [accent, deep.opacity(0.9)]),
      startPoint: CGPoint(x: 60, y: 35), endPoint: CGPoint(x: 120, y: 130)))
    context.stroke(path, with: .color(.white.opacity(0.24)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
  }

  private func rod(_ points: [(CGFloat, CGFloat)], width: CGFloat) {
    line(points, color: frame, width: width)
    line(points.map { ($0.0 - 1, $0.1 - 1) }, color: steel, width: max(1, width * 0.4))
  }

  private func line(_ points: [(CGFloat, CGFloat)], color: Color, width: CGFloat) {
    guard let first = points.first else { return }
    var path = Path()
    path.move(to: CGPoint(x: first.0, y: first.1))
    for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
  }

  private func polygonPath(_ points: [(CGFloat, CGFloat)]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: CGPoint(x: first.0, y: first.1))
    for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
    path.closeSubpath()
    return path
  }

  private func polygon(_ points: [(CGFloat, CGFloat)], _ color: Color) {
    context.fill(polygonPath(points), with: .color(color))
  }

  private func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height)), with: .color(color))
  }

  private func gradientEllipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, colors: [Color]) {
    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height)),
      with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: x, y: y),
        endPoint: CGPoint(x: x + width, y: y + height)))
  }

  private func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat, color: Color) {
    context.fill(Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius), with: .color(color))
  }
}
