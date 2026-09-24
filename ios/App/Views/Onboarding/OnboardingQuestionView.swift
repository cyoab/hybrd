import SwiftUI

struct OnboardingQuestionView: View {
  @Environment(OnboardingStore.self) private var onboarding
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var customizeEquipment = false

  var body: some View {
    @Bindable var store = onboarding
    Group {
      switch onboarding.step {
      case .identity: identity($store.draft)
      case .goals: goals($store.draft)
      case .balance: balance
      case .running: running($store.draft)
      case .strength: strength($store.draft)
      case .body: bodyDetails($store.draft)
      case .rhythm: rhythm($store.draft)
      case .equipment: equipment
      case .focus: focus
      case .readiness: readiness($store.draft)
      case .connections: connections($store.draft)
      case .summary, .paywall: EmptyView()
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private func identity(_ draft: Binding<OnboardingDraft>) -> some View {
    VStack(alignment: .leading, spacing: 24) {
      ProfileIllustration(artwork: .identity).frame(height: 160).frame(maxWidth: .infinity)
      VStack(alignment: .leading, spacing: 10) {
        Text(L10n.text("Your name")).font(.subheadline.weight(.semibold))
        TextField(L10n.text("What you like to be called"), text: draft.name)
          .textContentType(.givenName).textInputAutocapitalization(.words).submitLabel(.done)
          .font(.title2.weight(.semibold)).padding(20)
          .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
      }
      note(L10n.text("This is a conversation about where you are, not a test of where you should be."), tone: .terra)
    }
  }
  private func goals(_ draft: Binding<OnboardingDraft>) -> some View {
    VStack(alignment: .leading, spacing: 22) {
      Text(L10n.text("My running goal")).font(.headline)
      ForEach(RunningGoal.allCases) { goal in
        OnboardingOption(title: goal.displayName, symbol: goal == .fitness ? "heart" : "flag.checkered",
          selected: onboarding.draft.runningGoal == goal) { onboarding.draft.runningGoal = goal }
      }
      if onboarding.draft.runningGoal != nil && onboarding.draft.runningGoal != .fitness {
        Toggle(L10n.text("I have a race date"), isOn: draft.hasRaceDate)
        if onboarding.draft.hasRaceDate {
          DatePicker(L10n.text("Race date"), selection: draft.raceDate, in: Date()..., displayedComponents: .date)
        }
      }
      Text(L10n.text("My strength goal")).font(.headline).padding(.top, 4)
      ForEach(StrengthGoal.allCases) { goal in
        OnboardingOption(title: goal.displayName, symbol: "dumbbell", tone: .violet,
          selected: onboarding.draft.strengthGoal == goal) { onboarding.draft.strengthGoal = goal }
      }
    }
  }
  private var balance: some View {
    VStack(spacing: 14) {
      OnboardingHero(compact: true)
      ForEach(TrainingPriority.allCases) { priority in
        OnboardingOption(title: priority.displayName, detail: priorityDetail(priority),
          symbol: priority == .balanced ? "circle.lefthalf.filled" : priority == .running ? "figure.run" : "dumbbell",
          tone: priority == .strength ? .violet : .terra, selected: onboarding.draft.priority == priority) {
          onboarding.draft.priority = priority
        }
      }
    }
  }
  private func priorityDetail(_ priority: TrainingPriority) -> String {
    switch priority {
    case .balanced: L10n.text("Make steady progress in both.")
    case .running: L10n.text("Protect my running goal and support it with strength.")
    case .strength: L10n.text("Prioritize lifting while keeping my engine strong.")
    }
  }
  private func running(_ draft: Binding<OnboardingDraft>) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Image("SessionShoe").resizable().scaledToFit().frame(height: 115).frame(maxWidth: .infinity).accessibilityHidden(true)
      experience(onboarding.draft.runningLevel, tone: .terra) { onboarding.draft.runningLevel = $0 }
      Text(L10n.text("A typical recent week")).font(.headline).padding(.top, 12)
      Picker(L10n.text("Distance units"), selection: Binding(get: { onboarding.draft.units.distance }, set: { onboarding.draft.setDistanceUnit($0) })) {
        ForEach(TrainingDistanceUnit.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented)
      numberField(L10n.text("Weekly running distance"), text: draft.weeklyDistance, unit: onboarding.draft.units.distance.symbol)
      Text(L10n.text("Think about the last few weeks, not a future target. Enter 0 if you aren’t running yet."))
        .font(.caption).foregroundStyle(HybrdStyle.muted)
    }
  }
  private func strength(_ draft: Binding<OnboardingDraft>) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Image("SessionDumbbell").resizable().scaledToFit().frame(height: 115).frame(maxWidth: .infinity).accessibilityHidden(true)
      experience(onboarding.draft.strengthLevel, tone: .violet) { onboarding.draft.strengthLevel = $0 }
      pickerCard(L10n.text("Current lifting days per week"), detail: L10n.text("How many days do you lift in a typical week right now?")) {
        Picker(L10n.text("Current lifting days per week"), selection: draft.currentLiftDays) {
          ForEach(0..<8) { Text(L10n.text("\($0) days per week")).tag(Double($0)) }
          if onboarding.draft.currentLiftDays.rounded() != onboarding.draft.currentLiftDays {
            Text(onboarding.draft.currentLiftDays.formatted()).tag(onboarding.draft.currentLiftDays)
          }
        }.pickerStyle(.menu).labelsHidden()
      }
      note(L10n.text("Different starting points, one athlete. Your running experience won’t decide your lifting level."), tone: .violet)
    }
  }
  private func experience(_ selected: TrainingExperience?, tone: SessionBreakdown.Tone, choose: @escaping (TrainingExperience) -> Void) -> some View {
    ForEach(TrainingExperience.allCases) { level in
      OnboardingOption(title: level.displayName, detail: level.detail, symbol: level == .new ? "sparkle" : "chart.bar",
        tone: tone, selected: selected == level) { choose(level) }
    }
  }
  private func bodyDetails(_ draft: Binding<OnboardingDraft>) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      ProfileIllustration(artwork: .identity).frame(height: 125).frame(maxWidth: .infinity)
      numberField(L10n.text("Age"), text: draft.age, unit: L10n.text("years"), keyboard: .numberPad)
      Picker(L10n.text("Weight units"), selection: Binding(get: { onboarding.draft.units.weight }, set: { onboarding.draft.setWeightUnit($0) })) {
        ForEach(TrainingWeightUnit.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented)
      numberField(L10n.text("Weight"), text: draft.weight, unit: onboarding.draft.units.weight.symbol)
      VStack(alignment: .leading, spacing: 12) {
        Text(L10n.text("Height")).font(.headline)
        Picker(L10n.text("Height units"), selection: Binding(get: { onboarding.draft.selectedHeightUnit }, set: { onboarding.draft.setHeightUnit($0) })) {
          ForEach(OnboardingHeightUnit.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented)
        if onboarding.draft.selectedHeightUnit == .centimeters {
          numberField(L10n.text("Height"), text: draft.height, unit: "cm")
        } else {
          let columns = [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 250 : 120))]
          LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            numberField(L10n.text("Feet"), text: Binding(get: { onboarding.draft.heightFeet ?? "" }, set: { onboarding.draft.heightFeet = $0 }), unit: "ft", keyboard: .numberPad)
            numberField(L10n.text("Inches"), text: Binding(get: { onboarding.draft.heightInches ?? "" }, set: { onboarding.draft.heightInches = $0 }), unit: "in")
          }
        }
      }
      note(L10n.text("Your body measurements aren’t a score. They’re optional context that you control."), tone: .terra)
    }
  }
  private func rhythm(_ draft: Binding<OnboardingDraft>) -> some View {
    VStack(alignment: .leading, spacing: 22) {
      ProfileIllustration(artwork: .rhythm).frame(height: 125).frame(maxWidth: .infinity)
      Text(L10n.text("Days you can train")).font(.headline)
      ScrollView(.horizontal) {
        HStack(spacing: 4) {
          ForEach(0..<7) { offset in
            let day = (Calendar.current.firstWeekday - 1 + offset) % 7 + 1
            Toggle(isOn: Binding(get: { onboarding.draft.availableDays.contains(day) }, set: { value in
              if value { onboarding.draft.availableDays.insert(day) } else { onboarding.draft.availableDays.remove(day) }
            })) {
              Text(Calendar.current.shortWeekdaySymbols[day - 1])
                .font(.caption.weight(.semibold)).frame(width: 44, height: 52)
                .foregroundStyle(onboarding.draft.availableDays.contains(day) ? HybrdStyle.primaryButtonText : HybrdStyle.ink)
                .background(onboarding.draft.availableDays.contains(day) ? HybrdStyle.primaryButton : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 15))
                .contentShape(RoundedRectangle(cornerRadius: 15))
            }.toggleStyle(.button).buttonStyle(.plain).accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
          }
        }
      }.scrollIndicators(.hidden)
      pickerCard(L10n.text("Preferred lifting days"), detail: L10n.text("How many days would you like to lift each week? Running and lifting can share a day.")) {
        Picker(L10n.text("Preferred lifting days"), selection: draft.strengthDays) {
          ForEach(1..<5) { Text(L10n.text("\($0) days per week")).tag($0) }
        }.pickerStyle(.menu).labelsHidden()
      }
      pickerCard(L10n.text("Time per session"), detail: L10n.text("How much time can you usually set aside for one workout?")) {
        Picker(L10n.text("Time per session"), selection: draft.sessionMinutes) {
          ForEach([30, 45, 60, 75, 90], id: \.self) { Text(L10n.text("\($0) min")).tag($0) }
        }.pickerStyle(.menu).labelsHidden()
      }
      note(L10n.text("Consistency beats a perfect week. Choose what you can repeat, with room to recover."), tone: .mint)
    }
  }
  private var equipment: some View {
    VStack(alignment: .leading, spacing: 16) {
      OnboardingOption(title: L10n.text("Full gym"), detail: L10n.text("Free weights, benches, cables and machines."), symbol: "building.2", tone: .violet,
        selected: onboarding.draft.equipmentConfirmed && onboarding.draft.equipment == fullGym) { setEquipment(fullGym) }
      OnboardingOption(title: L10n.text("Home essentials"), detail: L10n.text("Dumbbells, a bench and resistance bands."), symbol: "house", tone: .violet,
        selected: onboarding.draft.equipmentConfirmed && onboarding.draft.equipment == homeGym) { setEquipment(homeGym) }
      OnboardingOption(title: L10n.text("Bodyweight"), detail: L10n.text("Just me and some space to move."), symbol: "figure.strengthtraining.functional", tone: .violet,
        selected: onboarding.draft.equipmentConfirmed && onboarding.draft.equipment.isEmpty) { setEquipment([]) }
      DisclosureGroup(L10n.text("Customize my equipment"), isExpanded: $customizeEquipment) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 250 : 140))], spacing: 12) {
          ForEach(GymEquipment.allCases) { item in
            Toggle(isOn: Binding(get: { onboarding.draft.equipment.contains(item) }, set: { selected in
              onboarding.draft.equipmentConfirmed = true
              if selected { onboarding.draft.equipment.insert(item) } else { onboarding.draft.equipment.remove(item) }
            })) { GymEquipmentCard(equipment: item, selected: onboarding.draft.equipment.contains(item)) }
              .toggleStyle(.button).buttonStyle(.plain).accessibilityLabel(item.title)
          }
        }.padding(.top, 12)
      }.font(.subheadline.weight(.semibold)).padding(.vertical, 8)
      note(L10n.text("A useful workout starts with what’s available. You can update your setup whenever it changes."), tone: .violet)
    }
  }
  private var fullGym: Set<GymEquipment> { [.dumbbells, .barbell, .plates, .bench, .rack, .cableMachine, .latPulldown, .legPress] }
  private var homeGym: Set<GymEquipment> { [.dumbbells, .bench, .bands] }
  private func setEquipment(_ items: Set<GymEquipment>) { onboarding.draft.equipment = items; onboarding.draft.equipmentConfirmed = true }

  private var focus: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 26) {
        MuscleIllustration(selected: onboarding.draft.focusMuscles, posterior: false)
        MuscleIllustration(selected: onboarding.draft.focusMuscles, posterior: true)
      }.frame(height: 200).padding(20).background(SessionPalette.wash(.violet), in: RoundedRectangle(cornerRadius: 28))
        .accessibilityHidden(true)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 250 : 140))], spacing: 10) {
        ForEach(MuscleGroup.allCases) { muscle in
          let selected = onboarding.draft.focusMuscles.contains(muscle)
          Toggle(isOn: Binding(get: { selected }, set: { value in
            if value { onboarding.draft.focusMuscles.insert(muscle) } else { onboarding.draft.focusMuscles.remove(muscle) }
          })) {
            HStack {
              Text(muscle.title).font(.subheadline.weight(.medium))
              Spacer(minLength: 3)
              Image(systemName: selected ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 52)
              .foregroundStyle(selected ? SessionPalette.ink(.violet) : HybrdStyle.ink)
              .background(selected ? SessionPalette.wash(.violet) : HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 16))
              .contentShape(RoundedRectangle(cornerRadius: 16))
          }.toggleStyle(.button).buttonStyle(.plain)
        }
      }
      Button(L10n.text("Keep a balanced focus")) { onboarding.draft.focusMuscles = [] }.frame(maxWidth: .infinity)
    }
  }
  private func readiness(_ draft: Binding<OnboardingDraft>) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(OnboardingReadiness.allCases) { option in
        OnboardingOption(title: option.title, detail: option.detail, symbol: option.symbol, tone: .mint,
          selected: onboarding.draft.readiness == option) { onboarding.draft.readiness = option }
      }
      Text(L10n.text("Anything else we should understand?" )).font(.headline).padding(.top, 10)
      TextField(L10n.text("Optional · schedule, preferences, or movements to avoid"), text: draft.context, axis: .vertical)
        .lineLimit(3...6).padding(18).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
      Text(L10n.text("This note is saved for review. It doesn’t automatically change workout prescriptions in this preview."))
        .font(.caption).foregroundStyle(HybrdStyle.muted)
    }
  }
  private func connections(_ draft: Binding<OnboardingDraft>) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      ProfileIllustration(artwork: .heart).frame(height: 150).frame(maxWidth: .infinity)
      connection(L10n.text("Apple Health"), detail: L10n.text("Body measurements and workout history, with your permission."), symbol: "heart.fill", value: draft.wantsHealth)
      connection(L10n.text("Strava"), detail: L10n.text("Recent running history to help describe your baseline."), symbol: "figure.run", value: draft.wantsStrava)
      note(L10n.text("These are preferences for later. No permissions are requested and no services are connected in this preview."), tone: .mint)
    }
  }
  private func connection(_ title: String, detail: String, symbol: String, value: Binding<Bool>) -> some View {
    Toggle(isOn: value) {
      HStack(spacing: 12) {
        Image(systemName: symbol).font(.title2).foregroundStyle(HybrdStyle.terraText).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(HybrdStyle.muted) }
      }
    }.tint(SessionPalette.mint).padding(20).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 22))
  }
  private func numberField(_ title: String, text: Binding<String>, unit: String, keyboard: UIKeyboardType = .decimalPad) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.subheadline.weight(.medium))
      HStack {
        TextField("—", text: text).keyboardType(keyboard).font(.system(.title, design: .rounded, weight: .semibold))
          .accessibilityLabel(title).accessibilityHint(unit)
        Text(unit).font(.subheadline).foregroundStyle(HybrdStyle.muted)
      }.padding(18).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    }
  }
  private func pickerCard<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.headline)
      Text(detail).font(.subheadline).foregroundStyle(HybrdStyle.muted).fixedSize(horizontal: false, vertical: true)
      content().frame(minHeight: 44).font(.headline)
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
  }
  private func note(_ text: String, tone: SessionBreakdown.Tone) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "sparkle").foregroundStyle(SessionPalette.ink(tone)).accessibilityHidden(true)
      Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(SessionPalette.wash(tone), in: RoundedRectangle(cornerRadius: 20))
  }
}
