import SwiftUI

struct AthleteInfoView: View {
  @Bindable var editor: AthleteProfileEditor
  @FocusState private var focused: Bool
  @State private var showBirthday = false
  @State private var birthDraft = Date()

  var body: some View {
    Form {
      Section {
        ProfileSectionHero(eyebrow: "Your foundation", title: "It starts with you.",
          subtitle: "A few details about the athlete behind the plan. Share only what you want to.",
          artwork: .identity, tone: .violet)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
      Section("Identity") {
        LabeledContent("Name") {
          TextField("Name", text: $editor.profile.name, prompt: Text("Your name")).labelsHidden()
            .textContentType(.name).multilineTextAlignment(.trailing).focused($focused).accessibilityLabel("Name")
        }
        Button {
          birthDraft = editor.details.birthDate ?? Calendar.current.date(byAdding: .year, value: -25, to: Date())!
          showBirthday = true
        } label: {
          LabeledContent("Date of birth", value: editor.details.birthDate?.formatted(date: .abbreviated, time: .omitted) ?? "Add")
        }
        if let age = editor.details.age() {
          LabeledContent("Age", value: "\(age) years")
          Button("Remove date of birth", role: .destructive) { editor.details.birthDate = nil }
        }
      }
      Section {
        ProfileMetricField(title: "Weight", text: $editor.weight, unit: editor.units.weight.symbol, tone: .terra)
          .keyboardType(.decimalPad).focused($focused).modifier(ProfileTintedRow(tone: .terra))
        ProfileMetricField(title: "Height", text: $editor.height, unit: "cm", tone: .sky)
          .keyboardType(.decimalPad).focused($focused).modifier(ProfileTintedRow(tone: .sky))
        if !editor.weight.isEmpty && editor.parsedWeightKilograms == nil {
          Text(editor.weightError).font(.caption).foregroundStyle(HybrdStyle.terraText)
        }
        if !editor.height.isEmpty && TrainingProfile.parseDecimal(editor.height, range: 80...250) == nil {
          Text("Enter 80–250 cm or leave height blank.").font(.caption).foregroundStyle(HybrdStyle.terraText)
        }
      } header: { Text("Body measurements") } footer: {
        Text("Optional. Enter your current measurements or import what you choose to share from Apple Health.")
      }
      Section {
        NavigationLink { ProfileConnectionsView(editor: editor) } label: {
          Label("Import from Apple Health", systemImage: "heart.text.clipboard")
            .foregroundStyle(SessionPalette.ink(.mint)).padding(.vertical, 5)
        }
      }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .sheet(isPresented: $showBirthday) {
      NavigationStack {
        Form {
          DatePicker("Date of birth", selection: $birthDraft,
            in: Calendar.current.date(byAdding: .year, value: -120, to: Date())!...Date(), displayedComponents: .date)
            .datePickerStyle(.graphical)
        }
        .navigationTitle("Date of birth").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showBirthday = false } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { editor.details.birthDate = birthDraft; showBirthday = false }
          }
        }
      }
    }
    .navigationTitle("About you").navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
  }
}
