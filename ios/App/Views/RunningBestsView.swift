import SwiftUI

struct RunningBestsView: View {
  @Bindable var editor: AthleteProfileEditor
  @FocusState private var focused: Bool

  var body: some View {
    Form {
      Section {
        Label("Every benchmark starts somewhere.", systemImage: "stopwatch")
          .font(.headline).foregroundStyle(HybrdStyle.terraText)
        Text("Add the distances you’ve raced or timed. Leave the rest blank.")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      Section {
        ForEach(RunRecordDistance.allCases) { distance in
          VStack(alignment: .leading, spacing: 6) {
            LabeledContent(distance.rawValue) {
              TextField("mm:ss", text: Binding(
                get: { editor.runningTimes[distance] ?? "" },
                set: { editor.runningTimes[distance] = $0 }))
                .labelsHidden().keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).monospacedDigit()
                .focused($focused).accessibilityLabel(distance.rawValue + " personal-best time")
            }
            if let value = editor.runningTimes[distance], !value.isEmpty, RunningPersonalBest.parse(value) == nil {
              Text("Use mm:ss or h:mm:ss.").font(.caption).foregroundStyle(HybrdStyle.terraText)
            }
          }
        }
      } header: { Text("Personal-best times") } footer: {
        Text("For example: 24:30 for a 5K or 1:48:20 for a half marathon. These are your recorded times, not pace estimates.")
      }
    }
    .navigationTitle("Running PRs").navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
  }
}
