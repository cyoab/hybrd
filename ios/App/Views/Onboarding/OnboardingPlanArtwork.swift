import SwiftUI

/// Running and lifting settle into the athlete's selected weekdays, not a generated prescription.
struct OnboardingPlanArtwork: View {
  var phase: OnboardingPreparationPhase
  var appeared: Bool
  var availableDays: Set<Int>
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var hasStrength: Bool { phase.rawValue >= OnboardingPreparationPhase.strength.rawValue }
  private var hasWeek: Bool { phase.rawValue >= OnboardingPreparationPhase.rhythm.rawValue }
  private var isTogether: Bool { phase == .together }
  private var settled: Bool { reduceMotion || hasWeek }

  var body: some View {
    GeometryReader { geometry in
      let scale = min(geometry.size.width / 340, geometry.size.height / 300)
      ZStack {
        Ellipse().fill(HybrdStyle.ink.opacity(0.055)).frame(width: 226, height: 17).blur(radius: 7)
          .offset(y: 132).opacity(hasWeek || reduceMotion ? 1 : 0)
        Circle().fill(SessionPalette.wash(.terra)).frame(width: 172, height: 172)
          .scaleEffect(settled ? 0.82 : 1).offset(x: -70, y: -46)
        Circle().fill(SessionPalette.wash(.violet)).frame(width: 144, height: 144)
          .scaleEffect(settled ? 0.86 : 1).offset(x: 81, y: -25)
          .opacity(hasStrength || reduceMotion ? 1 : 0.3)

        OnboardingPlanTrail(fromRight: false).trim(from: 0, to: appeared || reduceMotion ? 1 : 0)
          .stroke(HybrdStyle.terra.opacity(0.42), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [3, 8]))
          .opacity(hasWeek ? 0.25 : 1)
        OnboardingPlanTrail(fromRight: true).trim(from: 0, to: hasStrength || reduceMotion ? 1 : 0)
          .stroke(SessionPalette.violet.opacity(0.5), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [3, 8]))
          .opacity(hasWeek ? 0.25 : 1)

        weekCard
          .scaleEffect(reduceMotion ? 1 : hasWeek ? 1 : 0.82)
          .rotationEffect(.degrees(reduceMotion || isTogether ? 0 : -4))
          .offset(y: reduceMotion || hasWeek ? 59 : 93)
          .opacity(reduceMotion || hasWeek ? 1 : 0)

        Image("SessionShoe").resizable().scaledToFit().frame(width: settled ? 139 : 202)
          .rotationEffect(.degrees(settled ? -13 : appeared ? -18 : -35))
          .offset(x: settled ? -79 : appeared ? -32 : -114, y: settled ? -77 : appeared ? -30 : 9)
          .opacity(appeared || reduceMotion ? 1 : 0)
        Image("SessionDumbbell").resizable().scaledToFit().frame(width: settled ? 112 : 152)
          .rotationEffect(.degrees(settled ? 14 : hasStrength ? 24 : 48))
          .offset(x: settled ? 85 : hasStrength ? 75 : 143, y: settled ? -71 : hasStrength ? -7 : -54)
          .opacity(hasStrength || reduceMotion ? 1 : 0)

        Image(systemName: "checkmark.seal.fill").font(.system(size: 44, weight: .medium))
          .symbolRenderingMode(.palette).foregroundStyle(HybrdStyle.surface, SessionPalette.mint)
          .shadow(color: SessionPalette.mint.opacity(0.18), radius: 8, y: 4)
          .scaleEffect(reduceMotion || isTogether ? 1 : 0.5)
          .rotationEffect(.degrees(reduceMotion || isTogether ? 0 : -20))
          .offset(x: 126, y: -12).opacity(isTogether ? 1 : 0)
        flourish("sparkle", x: -134, y: 22, size: 19, tone: .terra)
        flourish("sparkle", x: 118, y: -125, size: 24, tone: .violet)
        flourish("circle.fill", x: 145, y: 82, size: 7, tone: .mint)
        flourish("circle.fill", x: -93, y: -132, size: 6, tone: .gold)
      }
      .frame(width: 340, height: 300)
      .scaleEffect(scale)
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .animation(reduceMotion ? nil : .spring(duration: 0.75, bounce: 0.16), value: phase)
    .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.12), value: appeared)
    .accessibilityHidden(true).allowsHitTesting(false)
  }

  private var weekCard: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 25).fill(SessionPalette.wash(.violet))
        .frame(width: 260, height: 138).rotationEffect(.degrees(isTogether || reduceMotion ? 4 : 9)).offset(x: 7, y: 6)
      RoundedRectangle(cornerRadius: 25).fill(SessionPalette.wash(.terra))
        .frame(width: 260, height: 138).rotationEffect(.degrees(isTogether || reduceMotion ? -4 : -10)).offset(x: -5, y: 3)
      VStack(alignment: .leading, spacing: 15) {
        HStack(spacing: 7) {
          Image(systemName: "calendar").foregroundStyle(SessionPalette.ink(.mint))
          Text(L10n.text("Your rhythm")).foregroundStyle(HybrdStyle.ink)
          Spacer()
          Circle().fill(HybrdStyle.terra).frame(width: 6, height: 6)
          RoundedRectangle(cornerRadius: 1.5).fill(SessionPalette.violet).frame(width: 6, height: 6)
        }.font(.system(size: 12, weight: .semibold))
        HStack(spacing: 6) {
          ForEach(0..<7) { offset in
            let day = (Calendar.current.firstWeekday - 1 + offset) % 7 + 1
            let selected = availableDays.contains(day)
            VStack(spacing: 8) {
              Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(HybrdStyle.muted)
              RoundedRectangle(cornerRadius: 7)
                .fill(selected ? SessionPalette.wash(isTogether ? .mint : .terra) : HybrdStyle.field)
                .frame(height: 30)
                .overlay {
                  if selected {
                    HStack(spacing: 3) {
                      Circle().fill(HybrdStyle.terra).frame(width: 5, height: 5)
                      RoundedRectangle(cornerRadius: 1.5).fill(SessionPalette.violet).frame(width: 5, height: 5)
                    }
                  } else { Capsule().fill(HybrdStyle.line).frame(width: 8, height: 2) }
                }
            }.frame(maxWidth: .infinity)
              .scaleEffect(hasWeek || reduceMotion ? 1 : 0.55, anchor: .bottom)
              .opacity(hasWeek || reduceMotion ? 1 : 0)
              .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2).delay(Double(offset) * 0.055), value: hasWeek)
          }
        }
      }.padding(20).frame(width: 270, height: 142)
        .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(HybrdStyle.line.opacity(0.75), lineWidth: 1))
        .shadow(color: HybrdStyle.ink.opacity(0.07), radius: 14, y: 8)
    }
  }

  private func flourish(_ symbol: String, x: CGFloat, y: CGFloat, size: CGFloat, tone: SessionBreakdown.Tone) -> some View {
    Image(systemName: symbol).font(.system(size: size)).foregroundStyle(SessionPalette.color(tone))
      .scaleEffect(reduceMotion || isTogether ? 1 : 0.3)
      .offset(x: x, y: y).opacity(isTogether ? 1 : 0)
  }
}

private struct OnboardingPlanTrail: Shape {
  var fromRight: Bool
  func path(in rect: CGRect) -> Path {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.width * (fromRight ? 1 - x : x), y: rect.height * y)
    }
    var path = Path()
    path.move(to: point(0.1, 0.65))
    path.addCurve(to: point(0.77, 0.3), control1: point(0.02, 0.05), control2: point(0.59, 0.03))
    return path
  }
}
