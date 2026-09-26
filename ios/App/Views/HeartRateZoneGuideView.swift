import SwiftUI

struct HeartRateZoneGuideView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(L10n.text("A target for every part of your run."))
            .font(.system(.title2, design: .rounded, weight: .semibold))
          Text(L10n.text("Zone targets describe the intended intensity in a five-zone system. The session ring shows planned time, not recorded heart rate."))
            .font(.subheadline).foregroundStyle(.secondary)
        }
        Section(L10n.text("The five zones")) {
          ForEach(HeartRateZone.allCases) { zone in
            HStack(spacing: 14) {
              Text(zone.shortTitle).font(.headline)
                .frame(width: 44, height: 44)
                .foregroundStyle(SessionPalette.ink(SessionBreakdown.tone(for: zone)))
                .background(SessionPalette.wash(SessionBreakdown.tone(for: zone)), in: RoundedRectangle(cornerRadius: 12))
              VStack(alignment: .leading, spacing: 4) {
                Text(zone.name).font(.headline)
                if let ranges = store.profile.athlete?.heartRateZones {
                  Text(ranges.label(for: zone)).font(.caption).foregroundStyle(.secondary)
                }
              }
            }.accessibilityElement(children: .combine)
          }
        }
        Section(L10n.text("Your BPM ranges")) {
          Text(store.profile.athlete?.heartRateZones == nil ?
            L10n.text("Add personal BPM ranges in Athlete profile → Heart-rate zones. These labels don’t estimate your maximum heart rate.") :
            L10n.text("These are the current BPM boundaries you saved in your athlete profile. They can be edited there at any time."))
          Text(L10n.text("Heart rate takes time to respond. During recovery, ease down and let it settle toward the target."))
        }.font(.subheadline).foregroundStyle(.secondary)
      }
      .navigationTitle(L10n.text("Heart-rate targets"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Done"), systemImage: "checkmark") { dismiss() }.labelStyle(.iconOnly)
        }
      }
    }
  }
}
