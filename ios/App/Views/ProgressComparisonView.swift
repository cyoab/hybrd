import SwiftUI
import Charts

struct ProgressComparisonView: View {
  var comparison: ProgressComparison
  private var tone: SessionBreakdown.Tone { comparison.kind == .run ? .terra : .violet }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(comparison.subtitle, systemImage: comparison.kind.symbol)
        .font(.caption.weight(.medium)).foregroundStyle(SessionPalette.ink(tone))
      Text(comparison.title).font(.headline)
      Text(comparison.changeLabel).font(.system(.title2, design: .rounded, weight: .semibold))
      ViewThatFits(in: .horizontal) {
        HStack { metric("First logged", comparison.first); Spacer(); Image(systemName: "arrow.right").accessibilityHidden(true); Spacer(); metric("Latest logged", comparison.latest) }
        VStack(alignment: .leading, spacing: 12) { metric("First logged", comparison.first); metric("Latest logged", comparison.latest) }
      }
      Chart(comparison.points) { point in
        LineMark(x: .value("Date", point.date), y: .value("Logged value", point.value))
          .foregroundStyle(SessionPalette.color(tone)).lineStyle(StrokeStyle(lineWidth: 3))
        PointMark(x: .value("Date", point.date), y: .value("Logged value", point.value))
          .foregroundStyle(SessionPalette.color(tone))
          .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
          .accessibilityValue(comparison.formatted(point.value))
      }
      .chartXAxis(.hidden).chartYAxis(.hidden)
      .chartYScale(domain: max(0, (comparison.points.map(\.value).min() ?? 0) * 0.85)...max(1, (comparison.points.map(\.value).max() ?? 1) * 1.1))
      .frame(height: 64).accessibilityLabel("Comparable logged efforts over time")
      Text(comparison.points.first!.date.formatted(date: .abbreviated, time: .omitted) + " → " +
        comparison.points.last!.date.formatted(date: .abbreviated, time: .omitted))
        .font(.caption2).foregroundStyle(HybrdStyle.muted)
      Label("Best logged · " + comparison.formatted(comparison.best.value) + " · " + comparison.best.date.formatted(.dateTime.month(.abbreviated).day()), systemImage: "medal")
        .font(.caption.weight(.medium)).foregroundStyle(SessionPalette.ink(tone))
      Text(comparison.kind == .run ? "Whole-session pace. Route, conditions, and effort can differ." :
        "Heaviest completed set at the same rep count in each session.")
        .font(.caption).foregroundStyle(HybrdStyle.muted)
    }
    .padding(20).background(SessionPalette.wash(tone).opacity(0.65), in: RoundedRectangle(cornerRadius: 25))
  }
  private func metric(_ label: String, _ value: Double) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label).font(.caption).foregroundStyle(HybrdStyle.muted)
      Text(comparison.formatted(value)).font(.title3.weight(.semibold)).monospacedDigit()
    }
  }
}
