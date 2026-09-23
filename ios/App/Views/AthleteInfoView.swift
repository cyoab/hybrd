import SwiftUI

struct AthleteInfoView: View {
  @Bindable var editor: AthleteProfileEditor
  @FocusState private var focused: Bool
  @State private var showBirthday = false
  @State private var birthDraft = Date()

  var body: some View {
    Form {
      Section {
        ProfileSectionHero(eyebrow: L10n.text("Your foundation"), title: L10n.text("It starts with you."),
          subtitle: L10n.text("A few details about the athlete behind the plan. Share only what you want to."),
          artwork: .identity, tone: .violet)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
      Section(L10n.text("Identity")) {
        LabeledContent(L10n.text("Name")) {
          TextField(L10n.text("Name"), text: $editor.profile.name, prompt: Text(L10n.text("Your name"))).labelsHidden()
            .textContentType(.name).multilineTextAlignment(.trailing).focused($focused).accessibilityLabel(L10n.text("Name"))
        }
        Button {
          birthDraft = editor.details.birthDate ?? Calendar.current.date(byAdding: .year, value: -25, to: Date())!
          showBirthday = true
        } label: {
          LabeledContent(L10n.text("Date of birth"), value: editor.details.birthDate?.formatted(date: .abbreviated, time: .omitted) ?? L10n.text("Add"))
        }
        if let age = editor.details.age() {
          LabeledContent(L10n.text("Age"), value: L10n.text("\(age) years"))
          Button(L10n.text("Remove date of birth"), role: .destructive) { editor.details.birthDate = nil }
        }
      }
      Section {
        ProfileMetricField(title: L10n.text("Weight"), text: $editor.weight, unit: editor.units.weight.symbol, tone: .terra)
          .keyboardType(.decimalPad).focused($focused).modifier(ProfileTintedRow(tone: .terra))
        ProfileMetricField(title: L10n.text("Height"), text: $editor.height, unit: "cm", tone: .sky)
          .keyboardType(.decimalPad).focused($focused).modifier(ProfileTintedRow(tone: .sky))
        if !editor.weight.isEmpty && editor.parsedWeightKilograms == nil {
          Text(editor.weightError).font(.caption).foregroundStyle(HybrdStyle.terraText)
        }
        if !editor.height.isEmpty && TrainingProfile.parseDecimal(editor.height, range: 80...250) == nil {
          Text(L10n.text("Enter 80–250 cm or leave height blank.")).font(.caption).foregroundStyle(HybrdStyle.terraText)
        }
      } header: { Text(L10n.text("Body measurements")) } footer: {
        Text(L10n.text("Optional. Enter your current measurements or import what you choose to share from Apple Health."))
      }
      Section {
        NavigationLink { ProfileConnectionsView(editor: editor) } label: {
          Label(L10n.text("Import from Apple Health"), systemImage: "heart.text.clipboard")
            .foregroundStyle(SessionPalette.ink(.mint)).padding(.vertical, 5)
        }
      }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .sheet(isPresented: $showBirthday) {
      NavigationStack {
        Form {
          DatePicker(L10n.text("Date of birth"), selection: $birthDraft,
            in: Calendar.current.date(byAdding: .year, value: -120, to: Date())!...Date(), displayedComponents: .date)
            .datePickerStyle(.graphical)
        }
        .navigationTitle(L10n.text("Date of birth")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { showBirthday = false } }
          ToolbarItem(placement: .confirmationAction) {
            Button(L10n.text("Done")) { editor.details.birthDate = birthDraft; showBirthday = false }
          }
        }
      }
    }
    .navigationTitle(L10n.text("About you")).navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(L10n.text("Done")) { focused = false } } }
  }
}
