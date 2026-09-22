import SwiftUI

struct TrainingPreferencesView: View {
  @Bindable var editor: AthleteProfileEditor
  @Environment(\.dynamicTypeSize) private var typeSize
  @FocusState private var distanceFocused: Bool
  private let weekdays = [(2, "Mon", "Monday"), (3, "Tue", "Tuesday"), (4, "Wed", "Wednesday"),
    (5, "Thu", "Thursday"), (6, "Fri", "Friday"), (7, "Sat", "Saturday"), (1, "Sun", "Sunday")]

  var body: some View {
    Form {
      Section {
        ProfileSectionHero(eyebrow: "Goals & rhythm", title: "Find your flow.",
          subtitle: "Set your direction, then make room for training in your week.",
          artwork: .rhythm, tone: .gold)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }

      Section {
        illustratedChoice("Running goal", artwork: .running, tone: .terra) {
          Picker("Running goal", selection: $editor.profile.runningGoal) {
            ForEach(RunningGoal.allCases) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.menu).labelsHidden()
        }
        illustratedChoice("Strength goal", artwork: .strength, tone: .violet) {
          Picker("Strength goal", selection: $editor.profile.strengthGoal) {
            ForEach(StrengthGoal.allCases) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.menu).labelsHidden()
        }
        illustratedChoice("Training focus", artwork: .experience, tone: .mint) {
          Picker("Training focus", selection: $editor.profile.priority) {
            ForEach(TrainingPriority.allCases) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.menu).labelsHidden()
        }
      } header: { Text("Your direction") }

      Section {
        VStack(alignment: .leading, spacing: 6) {
          ProfileMetricField(title: "Weekly running distance", text: $editor.weeklyDistance,
            unit: "km / week", tone: .terra, placeholder: "e.g. 70")
            .keyboardType(.decimalPad).focused($distanceFocused)
            .accessibilityHint("Enter any distance from 3 to 150 kilometers.")
          if TrainingProfile.parseWeeklyKilometers(editor.weeklyDistance) == nil {
            Label("Enter a distance from 3 to 150 km.", systemImage: "exclamationmark.circle")
              .font(.caption).foregroundStyle(HybrdStyle.terraText)
          } else {
            Text("Tap the number to edit. Decimals welcome.")
              .font(.caption).foregroundStyle(HybrdStyle.muted)
          }
        }
        .padding(.bottom, 6).modifier(ProfileTintedRow(tone: .terra))
      } header: { Text("Your weekly rhythm") } footer: {
        Text("Use a recent, comfortable weekly distance. Your available days and session length may limit the distance in your starter block.")
      }

      Section {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
              Text("Strength sessions").font(.headline)
              Text("Each week").font(.subheadline).foregroundStyle(HybrdStyle.muted)
            }
            Spacer(minLength: 0)
            Text(String(editor.profile.strengthDays))
              .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
              .foregroundStyle(SessionPalette.ink(.violet)).accessibilityHidden(true)
          }
          Picker("Strength sessions per week", selection: $editor.profile.strengthDays) {
            ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
          }.pickerStyle(.segmented).labelsHidden()
        }.padding(.vertical, 8).modifier(ProfileTintedRow(tone: .violet))
      }

      Section {
        illustratedChoice("Time per session", artwork: .rhythm, tone: .sky) {
          Picker("Time per session", selection: $editor.profile.sessionMinutes) {
            ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0) minutes").tag($0) }
          }.pickerStyle(.menu).labelsHidden()
        }
      }

      Section {
        VStack(alignment: .leading, spacing: 16) {
          let heading = typeSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
          heading {
            Text("Your training days").font(.headline)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text("\(editor.profile.availableDays.count) selected")
              .font(.caption.weight(.medium)).foregroundStyle(SessionPalette.ink(.mint))
          }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 88 : 62))], spacing: 10) {
            ForEach(weekdays, id: \.0) { day, shortName, name in
              let selected = editor.profile.availableDays.contains(day)
              Toggle(isOn: Binding(
                get: { editor.profile.availableDays.contains(day) },
                set: { enabled in
                  if enabled { editor.profile.availableDays.insert(day) }
                  else { editor.profile.availableDays.remove(day) }
                }
              )) {
                VStack(spacing: 9) {
                  Text(shortName).font(.subheadline.weight(.semibold))
                  Image(systemName: selected ? "checkmark" : "minus").font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 62).padding(.vertical, 5)
                .foregroundStyle(selected ? HybrdStyle.primaryButtonText : HybrdStyle.muted)
                .background(selected ? HybrdStyle.primaryButton : HybrdStyle.surface,
                  in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16)
                  .strokeBorder(selected ? Color.clear : HybrdStyle.line))
                .contentShape(RoundedRectangle(cornerRadius: 16))
              }
              .toggleStyle(.button).buttonStyle(.plain).accessibilityLabel(name)
            }
          }
          if editor.profile.availableDays.count < 2 {
            Label("Choose at least two training days.", systemImage: "exclamationmark.circle")
              .font(.caption).foregroundStyle(HybrdStyle.terraText)
          }
        }.padding(.vertical, 8).modifier(ProfileTintedRow(tone: .mint))
      } header: { Text("Make room for training") } footer: {
        Text("Choose days that work for you. Your starter block keeps at least one for running and fits strength into the remaining days.")
      }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .navigationTitle("Goals & rhythm").navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { distanceFocused = false }
      }
    }
  }

  private func illustratedChoice<Choice: View>(_ title: String, artwork: ProfileIllustration.Artwork,
    tone: SessionBreakdown.Tone, @ViewBuilder choice: () -> Choice) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 12) {
        Text(title).font(.subheadline.weight(.medium)).foregroundStyle(SessionPalette.ink(tone))
          .accessibilityHidden(true)
        choice().font(.headline).tint(SessionPalette.ink(tone))
          .frame(minHeight: 44).contentShape(Rectangle())
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if !typeSize.isAccessibilitySize {
        ProfileIllustration(artwork: artwork).frame(width: 66, height: 66)
      }
    }
    .padding(.vertical, 7).modifier(ProfileTintedRow(tone: tone))
  }
}
