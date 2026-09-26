import SwiftUI

struct WeeklyProgressView: View {
  @Environment(\.trainingUnits) private var units
  var summary: WeeklyTrainingSummary
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) :
      AnyLayout(HStackLayout(alignment: .top, spacing: 10))
    layout {
      tile(title: L10n.text("Running"), symbol: "figure.run",
        value: distanceNumber(summary.loggedMeters), unit: units.distance.symbol,
        goal: runningGoal,
        progress: summary.runningProgress, tone: .terra,
        accessibility: L10n.text("\(distanceNumber(summary.loggedMeters)) \(units.distance.title.lowercased()) logged. ") + runningGoal + L10n.text(" this week"))
      tile(title: L10n.text("Strength"), symbol: "dumbbell",
        value: "\(summary.loggedLifts)", unit: L10n.text("logged"),
        goal: L10n.text("of \(summary.plannedLifts) sessions"),
        progress: summary.liftingProgress, tone: .violet,
        accessibility: L10n.text("\(summary.loggedLifts) strength sessions logged of \(summary.plannedLifts) planned this week"))
    }
  }

  private var runningGoal: String {
    let distance = L10n.text("of \(distanceNumber(summary.plannedMeters)) \(units.distance.symbol) planned")
    guard summary.timedRuns > 0 else { return distance }
    let timed = L10n.text("\(summary.timedRuns) timed runs")
    return summary.plannedMeters > 0 ? distance + " + " + timed : L10n.text("\(timed) planned")
  }

  private func distanceNumber(_ meters: Int) -> String {
    units.distanceNumber(Double(meters))
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
