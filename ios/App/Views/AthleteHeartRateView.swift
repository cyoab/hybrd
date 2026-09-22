import SwiftUI

struct AthleteHeartRateView: View {
  @Bindable var editor: AthleteProfileEditor
  @FocusState private var focused: Bool

  var body: some View {
    Form {
      Section {
        ProfileSectionHero(eyebrow: "Find your rhythm", title: "Your heart. Your zones.",
          subtitle: "Give every run a personal effort range. Enter the boundaries you already use.",
          artwork: .heart, tone: .terra)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
      Section {
        HStack(spacing: 12) {
          zoneMark(.one)
          VStack(alignment: .leading, spacing: 5) {
            Text("Recovery").font(.headline)
            Text(editor.zones?.label(for: .one) ?? "Below the start of Zone 2")
              .font(.subheadline).foregroundStyle(HybrdStyle.muted)
          }
        }.padding(.vertical, 7)
          .accessibilityElement(children: .combine)
          .modifier(ProfileTintedRow(tone: .sky))
      } header: { Text("Your five zones") }

      ForEach(Array(HeartRateZone.allCases.dropFirst())) { zone in
        let index = zone.rawValue - 2
        let tone = SessionBreakdown.tone(for: zone)
        Section {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
              zoneMark(zone)
              VStack(alignment: .leading, spacing: 4) {
                Text(zone.name).font(.headline)
                if let ranges = editor.zones {
                  Text(ranges.label(for: zone)).font(.caption).foregroundStyle(HybrdStyle.muted)
                }
              }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text("Starts at").font(.subheadline).foregroundStyle(HybrdStyle.muted)
              Spacer(minLength: 0)
              TextField("Zone boundary", text: $editor.zoneStarts[index], prompt: Text("Not set")).labelsHidden()
                .keyboardType(.numberPad).focused($focused).multilineTextAlignment(.trailing)
                .font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                .accessibilityLabel("Zone \(zone.rawValue) starts at, beats per minute")
              Text("bpm").font(.subheadline).foregroundStyle(HybrdStyle.muted)
            }
          }
          .padding(.vertical, 8)
          .modifier(ProfileTintedRow(tone: tone))
        }
      }
      if editor.zoneStarts.contains(where: { !$0.isEmpty }) && editor.zones == nil {
        Section {
          Label("Enter four increasing boundaries from 30–250 bpm.", systemImage: "exclamationmark.circle")
            .font(.subheadline).foregroundStyle(HybrdStyle.terraText)
        }
      }
      Section {
        Button("Clear personal zones", role: .destructive) { editor.zoneStarts = ["", "", "", ""] }
          .disabled(editor.zoneStarts.allSatisfy(\.isEmpty))
      } footer: {
        Text("Use your tested or configured zones. Zone 5 has no upper limit here. We don’t estimate zones from age, and Apple Health’s profile import doesn’t include Apple Watch zone settings.")
      }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .navigationTitle("Heart-rate zones").navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
  }

  private func zoneMark(_ zone: HeartRateZone) -> some View {
    Text(zone.shortTitle).font(.headline.monospacedDigit())
      .foregroundStyle(SessionPalette.ink(SessionBreakdown.tone(for: zone)))
      .frame(minWidth: 42, minHeight: 42)
      .background(SessionPalette.color(SessionBreakdown.tone(for: zone)).opacity(0.18),
        in: RoundedRectangle(cornerRadius: 13))
      .accessibilityLabel(zone.title)
  }
}
