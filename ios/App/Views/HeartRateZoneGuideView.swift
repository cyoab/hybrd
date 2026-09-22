import SwiftUI

struct HeartRateZoneGuideView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("A target for every part of your run.")
            .font(.system(.title2, design: .rounded, weight: .semibold))
          Text("Zone targets describe the intended intensity in a five-zone system. The session ring shows planned time, not recorded heart rate.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        Section("The five zones") {
          ForEach(HeartRateZone.allCases) { zone in
            HStack(spacing: 14) {
              Text(zone.shortTitle).font(.headline)
                .frame(width: 44, height: 44)
                .foregroundStyle(SessionPalette.ink(SessionBreakdown.tone(for: zone)))
                .background(SessionPalette.wash(SessionBreakdown.tone(for: zone)), in: RoundedRectangle(cornerRadius: 12))
              Text(zone.name).font(.headline)
            }.accessibilityElement(children: .combine)
          }
        }
        Section("Your BPM ranges") {
          Text("Personal BPM boundaries aren’t connected in hybrd yet. Use your own configured five-zone ranges; these labels don’t estimate your maximum heart rate.")
          Text("Heart rate takes time to respond. During recovery, ease down and let it settle toward the target.")
        }.font(.subheadline).foregroundStyle(.secondary)
      }
      .navigationTitle("Heart-rate targets")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly)
        }
      }
    }
  }
}
