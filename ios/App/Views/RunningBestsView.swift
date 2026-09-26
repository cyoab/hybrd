import SwiftUI

struct RunningBestsView: View {
  @Bindable var editor: AthleteProfileEditor
  @FocusState private var focused: Bool

  var body: some View {
    Form {
      Section {
        ProfileSectionHero(eyebrow: L10n.text("Running PRs"), title: L10n.text("Your fastest times."),
          subtitle: L10n.text("From your first mile to your fastest marathon. Add the distances you’ve raced or timed."),
          artwork: .running, tone: .terra)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
      ForEach(RunRecordDistance.allCases) { distance in
        Section {
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
              Text(distance.displayName).font(.headline).foregroundStyle(HybrdStyle.ink)
              Spacer()
              if let time = editor.runningTimes[distance], RunningPersonalBest.parse(time) != nil {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(HybrdStyle.terraText)
                  .accessibilityLabel(L10n.text("Time entered"))
              }
            }
            ProfileMetricField(title: L10n.text("Personal best"), text: Binding(
              get: { editor.runningTimes[distance] ?? "" },
              set: { editor.runningTimes[distance] = $0 }), unit: "", tone: .terra, placeholder: L10n.text("mm:ss"),
              accessibilityTitle: L10n.text("\(distance.displayName) personal-best time"))
              .keyboardType(.numbersAndPunctuation).focused($focused)
            if let value = editor.runningTimes[distance], !value.isEmpty, RunningPersonalBest.parse(value) == nil {
              Text(L10n.text("Use mm:ss or h:mm:ss.")).font(.caption).foregroundStyle(HybrdStyle.terraText)
            }
          }
          .padding(.vertical, 4)
          .modifier(ProfileTintedRow(tone: .terra))
        }
      }
      Section {
        Text(L10n.text("Leave unrecorded distances blank. Use mm:ss or h:mm:ss, such as 24:30 or 1:48:20."))
          .font(.subheadline).foregroundStyle(HybrdStyle.muted)
      }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .navigationTitle(L10n.text("Running PRs")).navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(L10n.text("Done")) { focused = false } } }
  }
}
