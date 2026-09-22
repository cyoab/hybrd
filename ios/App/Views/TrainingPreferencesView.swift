import SwiftUI

struct TrainingPreferencesView: View {
  @Bindable var editor: AthleteProfileEditor
  @Environment(\.dynamicTypeSize) private var typeSize
  @FocusState private var focusedField: Field?
  private enum Field: Hashable { case distance }
  private let weekdays = [(2, "Mon", "Monday"), (3, "Tue", "Tuesday"), (4, "Wed", "Wednesday"),
    (5, "Thu", "Thursday"), (6, "Fri", "Friday"), (7, "Sat", "Saturday"), (1, "Sun", "Sunday")]
  var body: some View {
    Form {
    Section {
      Picker("Running goal", systemImage: "figure.run", selection: $editor.profile.runningGoal) {
        ForEach(RunningGoal.allCases) { Text($0.rawValue).tag($0) }
      }
      Picker("Strength goal", systemImage: "dumbbell", selection: $editor.profile.strengthGoal) {
        ForEach(StrengthGoal.allCases) { Text($0.rawValue).tag($0) }
      }
      Picker("Focus", systemImage: "scope", selection: $editor.profile.priority) {
        ForEach(TrainingPriority.allCases) { Text($0.rawValue).tag($0) }
      }
    } header: { Text("01 · Your direction") }

    Section {
      VStack(alignment: .leading, spacing: 12) {
        Label("Weekly running distance", systemImage: "figure.run").font(.subheadline.weight(.medium))
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          TextField("24", text: $editor.weeklyDistance)
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .distance)
            .accessibilityLabel("Weekly running distance in kilometers")
            .accessibilityHint("Enter any distance from 3 to 150 kilometers.")
            .fixedSize(horizontal: false, vertical: true)
          Text("km / week").font(.subheadline).foregroundStyle(HybrdStyle.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
          .stroke(focusedField == .distance ? HybrdStyle.terra : HybrdStyle.line, lineWidth: 1))
        if TrainingProfile.parseWeeklyKilometers(editor.weeklyDistance) == nil {
          Label("Enter a distance from 3 to 150 km.", systemImage: "exclamationmark.circle")
            .font(.caption).foregroundStyle(HybrdStyle.terraText)
        } else {
          Text("Tap the number to edit. Decimals welcome.")
            .font(.caption).foregroundStyle(HybrdStyle.muted)
        }
      }.padding(.vertical, 8)

      VStack(alignment: .leading, spacing: 12) {
        Text("Strength sessions / week").font(.subheadline.weight(.medium))
        Picker("Strength sessions per week", selection: $editor.profile.strengthDays) {
          ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
        }.pickerStyle(.segmented)
      }.padding(.vertical, 8)

      Picker("Time per session", systemImage: "clock", selection: $editor.profile.sessionMinutes) {
        ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0) minutes").tag($0) }
      }
    } header: { Text("02 · Your current rhythm") } footer: {
      Text("Use a recent, comfortable weekly distance. Your available days and session length may limit the distance in your starter block.")
    }

    Section {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 88 : 62))], spacing: 10) {
        ForEach(weekdays, id: \.0) { day, shortName, name in
          Toggle(isOn: Binding(
            get: { editor.profile.availableDays.contains(day) },
            set: { enabled in
              if enabled { editor.profile.availableDays.insert(day) }
              else { editor.profile.availableDays.remove(day) }
            }
          )) {
            VStack(spacing: 8) {
              Text(shortName).font(.subheadline.weight(.medium))
              Image(systemName: editor.profile.availableDays.contains(day) ? "checkmark" : "minus")
                .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 5)
            .foregroundStyle(editor.profile.availableDays.contains(day) ? HybrdStyle.primaryButtonText : HybrdStyle.muted)
            .background(editor.profile.availableDays.contains(day) ? HybrdStyle.primaryButton : HybrdStyle.field,
              in: RoundedRectangle(cornerRadius: 16))
          }
          .toggleStyle(.button).buttonStyle(.plain)
          .accessibilityLabel(name)
        }
      }.padding(.vertical, 8)
    } header: {
      HStack {
        Text("03 · Make room for training")
        Spacer()
        Text("\(editor.profile.availableDays.count) days")
      }
    } footer: {
      Text(editor.profile.availableDays.count < 2
        ? "Choose at least two training days to continue."
        : "Choose days that work for you. We’ll keep at least one for running and fit strength into the remaining days.")
    }

    }
    .navigationTitle("Training rhythm")
    .navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { focusedField = nil }
      }
    }
  }
}
