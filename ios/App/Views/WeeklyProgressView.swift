import SwiftUI

struct WeeklyProgressView: View {
  var summary: WeeklyTrainingSummary
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) :
      AnyLayout(HStackLayout(alignment: .top, spacing: 10))
    layout {
      tile(title: "Running", symbol: "figure.run",
        value: kilometers(summary.loggedMeters), unit: "km",
        goal: runningGoal,
        progress: summary.runningProgress, tone: .terra,
        accessibility: "\(kilometers(summary.loggedMeters)) kilometers logged. " + runningGoal + " this week")
      tile(title: "Strength", symbol: "dumbbell",
        value: "\(summary.loggedLifts)", unit: "logged",
        goal: "of \(summary.plannedLifts) sessions",
        progress: summary.liftingProgress, tone: .violet,
        accessibility: "\(summary.loggedLifts) strength sessions logged of \(summary.plannedLifts) planned this week")
    }
  }

  private var runningGoal: String {
    let distance = "of \(kilometers(summary.plannedMeters)) km planned"
    guard summary.timedRuns > 0 else { return distance }
    let timed = "\(summary.timedRuns) timed " + (summary.timedRuns == 1 ? "run" : "runs")
    return summary.plannedMeters > 0 ? distance + " + " + timed : timed + " planned"
  }

  private func kilometers(_ meters: Int) -> String {
    (Double(meters) / 1_000).formatted(.number.precision(.fractionLength(0...1)))
  }

  private func tile(title: String, symbol: String, value: String, unit: String, goal: String,
    progress: Double, tone: SessionBreakdown.Tone, accessibility: String) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title).font(.caption.weight(.semibold)).foregroundStyle(SessionPalette.ink(tone))
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text(value).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.75)
          Text(unit).font(.caption).foregroundStyle(HybrdStyle.muted)
        }
        Spacer(minLength: 0)
        ZStack {
          Circle().stroke(SessionPalette.color(tone).opacity(0.15), lineWidth: 4)
          Circle().trim(from: 0, to: progress)
            .stroke(SessionPalette.color(tone), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
          Image(systemName: symbol).font(.subheadline).foregroundStyle(SessionPalette.ink(tone))
        }
        .frame(width: 34, height: 34).padding(2)
      }
      Text(goal).font(.caption2).foregroundStyle(HybrdStyle.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(HybrdStyle.ink)
    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    .background(SessionPalette.wash(tone), in: RoundedRectangle(cornerRadius: 22))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(accessibility)
  }
}
