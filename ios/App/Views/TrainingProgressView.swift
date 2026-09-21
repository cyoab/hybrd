import SwiftUI
import Charts

struct TrainingProgressView: View {
  @Environment(TrainingStore.self) private var store
  private var completed: [WorkoutResult] { store.state.results.filter { $0.status != .skipped } }
  private var distance: Double { Double(completed.reduce(0) { $0 + ($1.distanceMeters ?? 0) }) / 1_000 }
  private var sets: Int { completed.reduce(0) { $0 + $1.sets.count } }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Both disciplines. Real work.")
            Text("Consistency adds up.").font(.largeTitle.bold()).tracking(-1)
            Text("Your logged training, together in one place.").foregroundStyle(.secondary)
          }
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(value: String(format: "%.1f km", distance), label: "Running completed", symbol: "figure.run")
            MetricTile(value: "\(sets)", label: "Strength sets completed", symbol: "dumbbell.fill")
          }
          if completed.isEmpty {
            ContentUnavailableView {
              Label("Your first session starts the story", systemImage: "chart.xyaxis.line")
            } description: {
              Text("Log a run or check off your strength sets. Your real progress will appear here.")
            }
            .padding(.vertical, 24)
          } else {
            VStack(alignment: .leading, spacing: 16) {
              Text("Last seven days").font(.title3.bold())
              Chart {
                ForEach(0..<7) { offset in
                  let day = TrainingEngine.date(Calendar.current.startOfDay(for: Date()), offset: offset - 6)
                  let results = completed.filter { Calendar.current.isDate($0.completedAt, inSameDayAs: day) }
                  ForEach(WorkoutKind.allCases) { kind in
                    BarMark(
                      x: .value("Day", day, unit: .day),
                      y: .value("Minutes", results.filter { $0.kind == kind }.reduce(0) { $0 + $1.durationSeconds } / 60)
                    )
                    .foregroundStyle(by: .value("Discipline", kind.rawValue))
                  }
                }
              }
              .chartForegroundStyleScale(["Run": HybrdStyle.run, "Strength": HybrdStyle.strength])
              .chartYAxisLabel("Minutes")
              .frame(height: 190)
              .accessibilityLabel("Logged training minutes over the last seven days")
            }
            .padding(20)
            .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 22))

            Text("Training history").font(.title3.bold())
            ForEach(completed.sorted { $0.completedAt > $1.completedAt }) { result in
              HStack(spacing: 14) {
                Image(systemName: result.kind.symbol).font(.title3).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 5) {
                  Text(result.kind.rawValue + " · " + result.status.rawValue).font(.headline)
                  Text(result.completedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(result.kind == .run ? String(format: "%.1f km", Double(result.distanceMeters ?? 0) / 1_000) : "\(result.sets.count) sets")
                  .font(.subheadline.monospacedDigit())
              }
              .padding(18)
              .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            }
          }
        }
        .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        .padding(20)
      }
      .background(HybrdStyle.background)
      .navigationTitle("Progress")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}
