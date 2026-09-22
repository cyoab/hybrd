import SwiftUI

struct AthleteHeartRateView: View {
  @Bindable var editor: AthleteProfileEditor
  @FocusState private var focused: Bool

  var body: some View {
    Form {
      Section {
        Text("Your zones, your effort.")
          .font(.system(.title2, design: .rounded, weight: .semibold))
        Text("Enter the start of Zones 2–5 from your tested or configured zones. Zone 1 sits below Zone 2; Zone 5 has no upper limit here.")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      Section("Zone boundaries") {
        ForEach(0..<4) { index in
          ProfileNumberField(title: "Zone \(index + 2) starts at", text: $editor.zoneStarts[index], unit: "bpm")
            .focused($focused)
        }
      }
      if let zones = editor.zones {
        Section("Your five zones") {
          ForEach(HeartRateZone.allCases) { zone in
            HStack {
              RunZoneBadge(zone: zone, personalZones: zones)
              Spacer()
              Text(zone.name).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
          }
        }
      } else if editor.zoneStarts.contains(where: { !$0.isEmpty }) {
        Section {
          Text("Enter all four boundaries in increasing order, from 30 to 250 bpm.")
            .foregroundStyle(HybrdStyle.terraText)
        }
      }
      Section {
        Button("Clear personal zones", role: .destructive) { editor.zoneStarts = ["", "", "", ""] }
      } footer: {
        Text("We don’t estimate zones from your age. Apple Health’s profile import doesn’t provide your Apple Watch zone settings.")
      }
    }
    .navigationTitle("Heart-rate zones").navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
  }
}
