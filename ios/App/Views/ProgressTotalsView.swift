import SwiftUI

struct ProgressTotalsView: View {
  var snapshot: ProgressSnapshot
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    layout {
      tile(value: (Double(snapshot.current.runMeters) / 1_000).formatted(.number.precision(.fractionLength(0...1))),
        unit: "km running", current: snapshot.current.runMeters, previous: snapshot.previous.runMeters,
        image: "SessionShoe", tone: .terra)
      tile(value: snapshot.current.strengthSets.formatted(), unit: "strength sets",
        current: snapshot.current.strengthSets, previous: snapshot.previous.strengthSets,
        image: "SessionDumbbell", tone: .violet)
    }
  }

  private func tile(value: String, unit: String, current: Int, previous: Int, image: String, tone: SessionBreakdown.Tone) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Image(image).resizable().scaledToFit().frame(height: 58).frame(maxWidth: .infinity, alignment: .trailing).accessibilityHidden(true)
      Text(value).font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
      Text(unit).font(.subheadline.weight(.medium))
      Text(change(current, previous)).font(.caption.weight(.semibold)).foregroundStyle(SessionPalette.ink(tone))
        .fixedSize(horizontal: false, vertical: true)
      Text(snapshot.period.comparisonLabel).font(.caption2).foregroundStyle(HybrdStyle.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading).padding(17)
    .background(SessionPalette.wash(tone), in: RoundedRectangle(cornerRadius: 24))
    .accessibilityElement(children: .combine)
  }
  private func change(_ current: Int, _ previous: Int) -> String {
    guard previous > 0 else { return current > 0 ? "A new baseline" : "Your next chapter awaits" }
    let change = Double(current - previous) / Double(previous)
    if abs(change) < 0.005 { return "Holding steady" }
    return abs(change).formatted(.percent.precision(.fractionLength(0))) + (change > 0 ? " more logged" : " less logged")
  }
}
