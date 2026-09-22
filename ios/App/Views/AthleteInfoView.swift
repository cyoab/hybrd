import SwiftUI

struct AthleteInfoView: View {
  @Bindable var editor: AthleteProfileEditor
  @FocusState private var focused: Bool
  @State private var showBirthday = false
  @State private var birthDraft = Date()

  var body: some View {
    Form {
      Section("Identity") {
        TextField("Name", text: $editor.profile.name).textContentType(.name).focused($focused)
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
        ProfileNumberField(title: "Weight", text: $editor.weight, unit: "kg").focused($focused)
        ProfileNumberField(title: "Height", text: $editor.height, unit: "cm").focused($focused)
        if !editor.weight.isEmpty && TrainingProfile.parseDecimal(editor.weight, range: 20...400) == nil {
          Text("Enter 20–400 kg or leave weight blank.").font(.caption).foregroundStyle(HybrdStyle.terraText)
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
        }
      }
    }
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

struct ProfileNumberField: View {
  var title: String
  @Binding var text: String
  var unit: String

  var body: some View {
    LabeledContent {
      HStack(spacing: 6) {
        TextField("Not set", text: $text).labelsHidden().keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing).monospacedDigit()
          .accessibilityLabel(title + " in " + unit)
        Text(unit).foregroundStyle(.secondary)
      }
    } label: { Text(title) }
  }
}
