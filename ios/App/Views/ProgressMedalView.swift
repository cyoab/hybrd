import SwiftUI

struct ProgressMedalView: View {
  var symbol: String
  var tone: SessionBreakdown.Tone
  var earned = true
  var level: Int?

  var body: some View {
    GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)
      ZStack {
        Circle().fill(SessionPalette.color(tone).opacity(0.09)).frame(width: size, height: size)
        ribbon.rotationEffect(.degrees(24)).offset(x: -size * 0.12, y: size * 0.22)
        ribbon.rotationEffect(.degrees(-24)).offset(x: size * 0.12, y: size * 0.22)
        ProgressMedallionShape()
          .fill(LinearGradient(colors: earned ? [SessionPalette.color(tone), SessionPalette.ink(tone)] : [HybrdStyle.line, HybrdStyle.field],
            startPoint: .topLeading, endPoint: .bottomTrailing))
          .frame(width: size * 0.77, height: size * 0.77)
          .rotationEffect(.degrees(-7)).offset(y: size * 0.03)
        ProgressMedallionShape()
          .fill(LinearGradient(colors: [HybrdStyle.surface, SessionPalette.wash(tone)], startPoint: .topLeading, endPoint: .bottomTrailing))
          .overlay(ProgressMedallionShape().strokeBorderless(SessionPalette.color(tone).opacity(earned ? 0.6 : 0.18)))
          .frame(width: size * 0.71, height: size * 0.71)
        Circle().stroke(SessionPalette.color(tone).opacity(earned ? 0.38 : 0.15), lineWidth: 2)
          .frame(width: size * 0.51, height: size * 0.51)
        if let level {
          Text(level.formatted()).font(.system(size: size * 0.3, weight: .bold, design: .rounded))
            .foregroundStyle(SessionPalette.ink(tone))
        } else {
          Image(systemName: earned ? symbol : "lock.fill")
            .font(.system(size: size * 0.23, weight: .semibold))
            .foregroundStyle(earned ? SessionPalette.ink(tone) : HybrdStyle.muted)
        }
        if earned {
          Image(systemName: "sparkle").font(.system(size: size * 0.12)).foregroundStyle(SessionPalette.color(tone))
            .offset(x: size * 0.4, y: -size * 0.27)
          Circle().fill(SessionPalette.color(tone)).frame(width: size * 0.04, height: size * 0.04)
            .offset(x: -size * 0.4, y: -size * 0.1)
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityHidden(true)
  }

  private var ribbon: some View {
    UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 3)
      .fill(earned ? SessionPalette.color(tone).opacity(0.7) : HybrdStyle.line)
      .frame(width: 22, height: 47)
  }
}

private struct ProgressMedallionShape: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      for index in 0..<6 {
        let angle = Double(index) * .pi / 3 - .pi / 2
        let point = CGPoint(x: rect.midX + cos(angle) * rect.width / 2, y: rect.midY + sin(angle) * rect.height / 2)
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      path.closeSubpath()
    }
  }
  func strokeBorderless(_ color: Color) -> some View { stroke(color, lineWidth: 1.5) }
}

enum ProgressTheme {
  static func tone(_ kind: ProgressMilestone.Kind) -> SessionBreakdown.Tone {
    switch kind {
    case .tenKilometers, .fiftyKilometers: .terra
    case .twentyFiveSets, .hundredSets: .violet
    case .bothDisciplines: .mint
    default: .gold
    }
  }
}
