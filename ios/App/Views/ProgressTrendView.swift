import SwiftUI
import Charts

struct ProgressTrendView: View {
  @Environment(\.trainingUnits) private var units
  var snapshot: ProgressSnapshot
  @State private var kind: WorkoutKind = .run
  @State private var selectedDate: Date?
  private var tone: SessionBreakdown.Tone { kind == .run ? .terra : .violet }
  private var selected: ProgressSnapshot.Day? {
    guard let selectedDate else { return nil }
    return snapshot.buckets.last { $0.date <= selectedDate } ?? snapshot.buckets.first
  }
  private func value(_ day: ProgressSnapshot.Day) -> Double {
    kind == .run ? units.distance.value(fromMeters: Double(day.runMeters)) : Double(day.strengthSets)
  }

  private func end(of day: ProgressSnapshot.Day) -> Date {
    Calendar.current.date(byAdding: .day, value: snapshot.period == .week ? 1 : 7, to: day.date)!
  }
  private func label(_ day: ProgressSnapshot.Day) -> String {
    let start = day.date.formatted(.dateTime.month(.abbreviated).day())
    guard snapshot.period != .week else { return start }
    return start + "–" + end(of: day).addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 17) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text(L10n.text("Your momentum")).font(.title3.weight(.semibold))
          Text(snapshot.period == .week ? L10n.text("Daily logged training") : L10n.text("Weekly totals in this period"))
            .font(.caption).foregroundStyle(HybrdStyle.muted)
        }
        Spacer(minLength: 0)
      }
      Picker(L10n.text("Training discipline"), selection: $kind) {
        Text(L10n.text("Running")).tag(WorkoutKind.run)
        Text(L10n.text("Strength")).tag(WorkoutKind.strength)
      }.pickerStyle(.segmented).labelsHidden()
      if let selected {
        Text(label(selected) + " · " +
          value(selected).formatted(.number.precision(.fractionLength(0...1))) + (kind == .run ? " " + units.distance.symbol : L10n.text(" sets")))
          .font(.subheadline.weight(.medium)).foregroundStyle(SessionPalette.ink(tone))
      } else {
        Text(kind == .run ? L10n.text("Distance · ") + units.distance.symbol : L10n.text("Completed sets")).font(.subheadline.weight(.medium))
      }
      Chart(snapshot.buckets) { day in
        let padding = end(of: day).timeIntervalSince(day.date) * 0.17
        RectangleMark(xStart: .value(L10n.text("From"), day.date.addingTimeInterval(padding)),
          xEnd: .value(L10n.text("To"), end(of: day).addingTimeInterval(-padding)),
          yStart: .value(L10n.text("Baseline"), 0), yEnd: .value(kind == .run ? units.distance.title : L10n.text("Sets"), value(day)))
          .foregroundStyle(LinearGradient(colors: [SessionPalette.color(tone), SessionPalette.color(tone).opacity(0.4)], startPoint: .top, endPoint: .bottom))
          .cornerRadius(5)
          .opacity(selected == nil || selected?.date == day.date ? 1 : 0.35)
          .accessibilityLabel(label(day))
          .accessibilityValue(value(day).formatted() + (kind == .run ? " " + units.distance.title.lowercased() : L10n.text(" sets")))
      }
      .chartXScale(domain: snapshot.start...end(of: snapshot.buckets.last!))
      .chartYScale(domain: 0...max(kind == .run ? 1 : 2, (snapshot.buckets.map(value).max() ?? 0) * 1.15))
      .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in
        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
      } }
      .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
      .chartXSelection(value: $selectedDate)
      .frame(height: 175)
      Text(snapshot.current.sessions == 0 ? L10n.text("Log a session to light up this chart.") : L10n.text("Touch the chart to explore. Today is still in progress."))
        .font(.caption).foregroundStyle(HybrdStyle.muted)
    }
    .padding(20).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 26))
    .onChange(of: kind) { selectedDate = nil }
    .onChange(of: snapshot.period) { selectedDate = nil }
  }
}
