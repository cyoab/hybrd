import SwiftUI

/// Original vector illustrations for hybrd; decorative, not performance charts.
struct WorkoutArtwork: View {
  var kind: WorkoutKind

  var body: some View {
    ZStack(alignment: .leading) {
      (kind == .run ? HybrdStyle.terraWash : HybrdStyle.obsidian)
      Canvas { context, size in
        if kind == .run {
          context.translateBy(x: size.width * 0.72, y: size.height * 0.55)
          context.rotate(by: .degrees(-28))
          for lane in 0..<5 {
            let inset = CGFloat(lane) * 13
            let rect = CGRect(x: -143 + inset, y: -93 + inset, width: 286 - inset * 2, height: 186 - inset * 2)
            let track = Path(roundedRect: rect, cornerRadius: rect.height / 2)
            context.stroke(track, with: .color(HybrdStyle.terra.opacity(0.22)), lineWidth: 1.5)
            if lane == 2 {
              context.stroke(track.trimmedPath(from: 0.08, to: 0.39), with: .color(HybrdStyle.terra),
                style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
          }
        } else {
          context.translateBy(x: size.width * 0.72, y: size.height * 0.52)
          context.rotate(by: .degrees(-24))
          let bar = Path(roundedRect: CGRect(x: -129, y: -5, width: 258, height: 10), cornerRadius: 5)
          context.fill(bar, with: .color(HybrdStyle.stone))
          for side in [-1.0, 1.0] {
            for plate in 0..<3 {
              let x = side * (63 + Double(plate) * 17) - 6
              let height = CGFloat(104 - plate * 24)
              let rect = CGRect(x: x, y: -height / 2, width: 12, height: height)
              context.fill(Path(roundedRect: rect, cornerRadius: 5),
                with: .color(plate == 0 ? HybrdStyle.terra : Color.white.opacity(0.7 - Double(plate) * 0.2)))
            }
          }
          for offset in [-1.0, 1.0] {
            let line = Path { path in
              path.move(to: CGPoint(x: -24, y: offset * 55))
              path.addLine(to: CGPoint(x: 32, y: offset * 55))
            }
            context.stroke(line, with: .color(Color.white.opacity(0.15)),
              style: StrokeStyle(lineWidth: 2, lineCap: .round))
          }
        }
      }
      VStack(alignment: .leading, spacing: 16) {
        Text(kind == .run ? "RUN" : "LIFT")
          .font(.caption.weight(.semibold)).tracking(3)
        Image(systemName: kind == .run ? "figure.run" : "figure.strengthtraining.traditional")
          .font(.system(size: 54, weight: .light))
      }
      .foregroundStyle(kind == .run ? HybrdStyle.ink : .white)
      .padding(.leading, 26)
    }
    .frame(height: 150)
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .accessibilityHidden(true)
  }
}
