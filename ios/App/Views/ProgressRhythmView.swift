import SwiftUI

struct ProgressRhythmView: View {
  var days: [ProgressSnapshot.Day]
  var select: (ProgressSnapshot.Day) -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .body) private var cellHeight = 44

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Every day leaves a mark.").font(.title3.weight(.semibold))
      Text("Last 4 weeks · tap a day to revisit your work")
        .font(.caption).foregroundStyle(HybrdStyle.muted)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: typeSize.isAccessibilitySize ? 4 : 7), spacing: 6) {
        if !typeSize.isAccessibilitySize { ForEach(days.prefix(7)) { day in
          Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption2)
            .foregroundStyle(HybrdStyle.muted).accessibilityHidden(true)
        } }
        ForEach(days) { day in
          Button { select(day) } label: {
            VStack(spacing: 3) {
              if typeSize.isAccessibilitySize { Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption2) }
              Text(day.date.formatted(.dateTime.day())).font(.caption.weight(.semibold)).monospacedDigit()
              HStack(spacing: 3) {
                if day.runMeters > 0 { Circle().fill(HybrdStyle.terra).frame(width: 4, height: 4) }
                if day.strengthSets > 0 { RoundedRectangle(cornerRadius: 1).fill(SessionPalette.violet).frame(width: 4, height: 4) }
                if day.results.isEmpty { Color.clear.frame(width: 4, height: 4) }
              }
            }
            .foregroundStyle(day.results.isEmpty ? HybrdStyle.muted : HybrdStyle.ink)
            .frame(maxWidth: .infinity).frame(minHeight: cellHeight)
            .background(background(day), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
          .accessibilityValue(day.results.isEmpty ? "No training logged" : "\(day.results.count) sessions, \(Double(day.runMeters) / 1_000, specifier: "%.1f") kilometers and \(day.strengthSets) strength sets")
        }
      }
      ViewThatFits {
        HStack(spacing: 16) { legend }
        VStack(alignment: .leading, spacing: 8) { legend }
      }.font(.caption)
    }
    .padding(20).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 26))
  }
  private func background(_ day: ProgressSnapshot.Day) -> LinearGradient {
    let run = day.runMeters > 0
    let lift = day.strengthSets > 0
    return LinearGradient(colors: [run ? SessionPalette.wash(.terra) : lift ? SessionPalette.wash(.violet) : HybrdStyle.field,
      lift ? SessionPalette.wash(.violet) : run ? SessionPalette.wash(.terra) : HybrdStyle.field], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
  @ViewBuilder private var legend: some View {
    Label("Run", systemImage: "circle.fill").foregroundStyle(HybrdStyle.terraText)
    Label("Lift", systemImage: "square.fill").foregroundStyle(SessionPalette.ink(.violet))
    Text("Rest counts, too.").foregroundStyle(HybrdStyle.muted)
  }
}
