import SwiftUI

struct TrainingPreferencesView: View {
  @Bindable var editor: AthleteProfileEditor
  @Environment(\.dynamicTypeSize) private var typeSize
  @FocusState private var distanceFocused: Bool
  private var weekdays: [(Int, String, String)] {
    let calendar = Calendar.current
    return [2, 3, 4, 5, 6, 7, 1].map { ($0, calendar.shortWeekdaySymbols[$0 - 1], calendar.weekdaySymbols[$0 - 1]) }
  }

  var body: some View {
    Form {
      Section {
        ProfileSectionHero(eyebrow: L10n.text("Goals & rhythm"), title: L10n.text("Find your flow."),
          subtitle: L10n.text("Set your direction, then make room for training in your week."),
          artwork: .rhythm, tone: .gold)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }

      Section {
        illustratedChoice(L10n.text("Running goal"), artwork: .running, tone: .terra) {
          Picker(L10n.text("Running goal"), selection: $editor.profile.runningGoal) {
            ForEach(RunningGoal.allCases) { Text($0.displayName).tag($0) }
          }.pickerStyle(.menu).labelsHidden()
        }
        illustratedChoice(L10n.text("Strength goal"), artwork: .strength, tone: .violet) {
          Picker(L10n.text("Strength goal"), selection: $editor.profile.strengthGoal) {
            ForEach(StrengthGoal.allCases) { Text($0.displayName).tag($0) }
          }.pickerStyle(.menu).labelsHidden()
        }
        illustratedChoice(L10n.text("Training focus"), artwork: .experience, tone: .mint) {
          Picker(L10n.text("Training focus"), selection: $editor.profile.priority) {
            ForEach(TrainingPriority.allCases) { Text($0.displayName).tag($0) }
          }.pickerStyle(.menu).labelsHidden()
        }
      } header: { Text(L10n.text("Your direction")) }

      Section {
        VStack(alignment: .leading, spacing: 6) {
          ProfileMetricField(title: L10n.text("Weekly running distance"), text: $editor.weeklyDistance,
            unit: editor.units.distance.symbol + L10n.text(" / week"), tone: .terra, placeholder: L10n.text("e.g. ") + editor.units.distanceNumber(70_000, decimals: 0))
            .keyboardType(.decimalPad).focused($distanceFocused)
            .accessibilityHint(editor.weeklyDistanceError)
          if editor.parsedWeeklyKilometers == nil {
            Label(editor.weeklyDistanceError, systemImage: "exclamationmark.circle")
              .font(.caption).foregroundStyle(HybrdStyle.terraText)
          } else {
            Text(L10n.text("Tap the number to edit. Decimals welcome."))
              .font(.caption).foregroundStyle(HybrdStyle.muted)
          }
        }
        .padding(.bottom, 6).modifier(ProfileTintedRow(tone: .terra))
      } header: { Text(L10n.text("Your weekly rhythm")) } footer: {
        Text(L10n.text("Use a recent, comfortable weekly distance. Your available days and session length may limit the distance in your starter block."))
      }

      Section {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
              Text(L10n.text("Strength sessions")).font(.headline)
              Text(L10n.text("Each week")).font(.subheadline).foregroundStyle(HybrdStyle.muted)
            }
            Spacer(minLength: 0)
            Text(String(editor.profile.strengthDays))
              .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
              .foregroundStyle(SessionPalette.ink(.violet)).accessibilityHidden(true)
          }
          Picker(L10n.text("Strength sessions per week"), selection: $editor.profile.strengthDays) {
            ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
          }.pickerStyle(.segmented).labelsHidden()
        }.padding(.vertical, 8).modifier(ProfileTintedRow(tone: .violet))
      }

      Section {
        illustratedChoice(L10n.text("Time per session"), artwork: .rhythm, tone: .sky) {
          Picker(L10n.text("Time per session"), selection: $editor.profile.sessionMinutes) {
            ForEach([30, 45, 60, 75, 90], id: \.self) { Text(L10n.text("\($0) minutes")).tag($0) }
          }.pickerStyle(.menu).labelsHidden()
        }
      }

      Section {
        VStack(alignment: .leading, spacing: 16) {
          let heading = typeSize.isAccessibilitySize ?
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
          heading {
            Text(L10n.text("Your training days")).font(.headline)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(L10n.text("\(editor.profile.availableDays.count) selected"))
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
            Label(L10n.text("Choose at least two training days."), systemImage: "exclamationmark.circle")
              .font(.caption).foregroundStyle(HybrdStyle.terraText)
          }
        }.padding(.vertical, 8).modifier(ProfileTintedRow(tone: .mint))
      } header: { Text(L10n.text("Make room for training")) } footer: {
        Text(L10n.text("Choose days that work for you. Your starter block keeps at least one for running and fits strength into the remaining days."))
      }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .navigationTitle(L10n.text("Goals & rhythm")).navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(L10n.text("Done")) { distanceFocused = false }
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
