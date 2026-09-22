import SwiftUI

/// Original vector diagram. Labels and toggles carry all selection semantics.
struct MuscleIllustration: View {
  var selected: Set<MuscleGroup>
  var posterior = false

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width / 100, size.height / 224)
      context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 224 * scale) / 2)
      context.scaleBy(x: scale, y: scale)
      let base = HybrdStyle.chartStone.opacity(0.4)
      let half = smooth([
        [45, 26], [44, 31], [28, 36], [23, 44], [17, 73], [10, 98],
        [8, 113], [12, 116], [15, 109], [18, 92], [26, 76], [30, 55],
        [32, 76], [31, 96], [29, 117], [30, 146], [32, 165], [30, 185],
        [32, 208], [27, 216], [38, 219], [42, 211], [42, 182], [45, 162],
        [48, 124], [50, 112], [50, 26]
      ])
      context.fill(half, with: .color(base))
      context.fill(mirrored(half), with: .color(base))
      context.fill(Path(ellipseIn: CGRect(x: 40, y: 2, width: 20, height: 25)), with: .color(base))

      func muscle(_ group: MuscleGroup, _ points: [[CGFloat]]) {
        let path = smooth(points)
        let highlighted = selected.contains(group) && (posterior || group != .calves)
        let fill = highlighted ? SessionPalette.violet : HybrdStyle.chartStone.opacity(0.7)
        context.fill(path, with: .color(fill))
        context.fill(mirrored(path), with: .color(fill))
      }
      muscle(.shoulders, [[28, 36], [35, 36], [32, 49], [25, 57], [22, 51]])
      muscle(posterior ? .triceps : .biceps, [[25, 56], [30, 53], [28, 70], [23, 79], [19, 77], [21, 65]])
      if posterior {
        muscle(.back, [[33, 43], [44, 38], [49, 48], [45, 64], [42, 83], [35, 76]])
        muscle(.glutes, [[32, 97], [43, 94], [49, 101], [48, 116], [39, 122], [31, 114]])
        muscle(.hamstrings, [[33, 122], [46, 121], [44, 143], [40, 160], [33, 157], [31, 138]])
      } else {
        muscle(.chest, [[32, 40], [46, 37], [49, 43], [49, 57], [41, 59], [32, 53]])
        for row in 0..<4 {
          let top = CGFloat(62 + row * 8)
          muscle(.core, [[43, top], [49, top - 1], [49, top + 6], [42, top + 7]])
        }
        muscle(.quadriceps, [[33, 110], [45, 114], [44, 137], [40, 158], [33, 157], [31, 137]])
      }
      muscle(.calves, [[34, 169], [42, 163], [41, 188], [36, 202], [31, 186]])
    }
    .aspectRatio(100.0 / 224, contentMode: .fit)
    .accessibilityHidden(true)
  }

  private func mirrored(_ path: Path) -> Path {
    path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100, ty: 0))
  }
  private func smooth(_ coordinates: [[CGFloat]]) -> Path {
    let points = coordinates.map { CGPoint(x: $0[0], y: $0[1]) }
    return Path { path in
      guard let first = points.first, let last = points.last else { return }
      path.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
      for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        path.addQuadCurve(to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2), control: current)
      }
      path.closeSubpath()
    }
  }
}
