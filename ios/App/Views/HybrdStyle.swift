import SwiftUI

enum HybrdStyle {
  static let lime = Color(red: 0.831, green: 0.961, blue: 0.416)
  static let ink = Color(red: 0.065, green: 0.09, blue: 0.075)
  static let run = Color("AccentColor")
  static let strength = Color(red: 0.42, green: 0.43, blue: 0.85)
  static let background = Color(uiColor: .systemGroupedBackground)
  static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct Eyebrow: View {
  var text: String
  var body: some View {
    Text(text.uppercased())
      .font(.caption.weight(.semibold))
      .tracking(1.5)
      .foregroundStyle(.secondary)
  }
}

struct SessionRow: View {
  var workout: TrainingWorkout
  var status: String
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: workout.kind.symbol)
        .font(.title3.weight(.semibold))
        .foregroundStyle(workout.kind == .run ? HybrdStyle.run : HybrdStyle.strength)
        .frame(width: 48, height: 48)
        .background((workout.kind == .run ? HybrdStyle.run : HybrdStyle.strength).opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(workout.title).font(.headline)
        Text(workout.summary).font(.subheadline).foregroundStyle(.secondary)
        Text(status).font(.caption.weight(.medium)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if status == "Completed" {
        Image(systemName: "checkmark").foregroundStyle(.tint)
      }
    }
    .padding(.vertical, 5)
    .accessibilityElement(children: .combine)
  }
}

struct MetricTile: View {
  var value: String
  var label: String
  var symbol: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: symbol).foregroundStyle(.tint).accessibilityHidden(true)
      Text(value).font(.title2.bold()).monospacedDigit()
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    .accessibilityElement(children: .combine)
  }
}
