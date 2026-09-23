import Foundation

enum OnboardingChecks {
  @MainActor static func run() throws {
    let suite = "hybrd.onboarding.tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "hybrd.onboarding.preview.v1"
    defaults.set("keep training history", forKey: "training")
    let store = OnboardingStore(defaults: defaults)
    precondition(!store.started && !store.completed && !store.enteredApp)
    store.begin()
    precondition(!store.advance() && store.step == .identity)
    precondition(!store.finishPreview())

    var draft = OnboardingDraft()
    draft.name = "  Alex  "
    draft.runningGoal = .halfMarathon
    draft.strengthGoal = .build
    draft.priority = .balanced
    draft.runningLevel = .beginner
    draft.strengthLevel = .intermediate
    draft.weeklyDistance = "0"
    draft.availableDays = [2, 4, 6]
    draft.equipmentConfirmed = true // An explicitly chosen bodyweight setup is valid.
    draft.readiness = .returning
    precondition(draft.displayName == "Alex")
    precondition(draft.validation(for: .paywall) == nil, "A beginner can start at zero without optional body details")
    draft.weeklyDistance = "70"
    for _ in 0..<10 {
      draft.setDistanceUnit(.miles)
      precondition(abs(draft.weeklyMeters! - 70_000) < 0.001)
      draft.setDistanceUnit(.kilometers)
      precondition(abs(draft.weeklyMeters! - 70_000) < 0.001)
    }
    draft.weight = "80"
    for _ in 0..<10 {
      draft.setWeightUnit(.pounds)
      precondition(abs(draft.weightKilograms! - 80) < 0.001)
      draft.setWeightUnit(.kilograms)
      precondition(abs(draft.weightKilograms! - 80) < 0.001)
    }
    var cleared = draft
    cleared.setDistanceUnit(.miles)
    let oldDistanceText = cleared.weeklyDistance
    cleared.weeklyDistance = ""; cleared.setDistanceUnit(.kilometers)
    cleared.weeklyDistance = oldDistanceText
    precondition(cleared.distanceBaseline == nil && cleared.weeklyMeters! < 70_000,
      "A cleared field must not resurrect a baseline expressed in a different unit")
    cleared.setWeightUnit(.pounds)
    let oldWeightText = cleared.weight
    cleared.weight = ""; cleared.setWeightUnit(.kilograms); cleared.weight = oldWeightText
    precondition(cleared.weightBaseline == nil && cleared.weightKilograms! > 80)
    for text in ["", "-1", "NaN", "inf", "70km", "250001"] {
      var invalid = draft; invalid.weeklyDistance = text
      precondition(invalid.validation(for: .running) != nil, "Reject invalid baseline: " + text)
    }
    var invalid = draft
    invalid.weight = "0"; precondition(invalid.validation(for: .body) != nil)
    invalid = draft; invalid.age = "130"; precondition(invalid.validation(for: .body) != nil)
    invalid = draft; invalid.height = "500"; precondition(invalid.validation(for: .body) != nil)
    invalid = draft; invalid.availableDays = [2]; precondition(invalid.validation(for: .rhythm) != nil)
    invalid = draft; invalid.availableDays = [2, 8]; precondition(invalid.validation(for: .rhythm) != nil)
    invalid = draft; invalid.strengthDays = 4; precondition(invalid.validation(for: .rhythm) != nil)
    invalid = draft; invalid.hasRaceDate = true; invalid.raceDate = .distantPast
    precondition(invalid.validation(for: .goals) != nil)
    invalid = draft; invalid.context = String(repeating: "a", count: 301)
    precondition(invalid.validation(for: .readiness) != nil)

    store.draft = draft
    precondition(!store.finishPreview(), "Completing is only possible from the paywall")
    for expected in OnboardingStep.allCases.dropFirst() {
      precondition(store.advance())
      precondition(store.step == expected)
    }
    precondition(!store.advance())
    store.draft.membership = .monthly
    precondition(store.finishPreview() && store.completed)
    precondition(!store.enteredApp, "Finishing setup does not automatically leave the recap")
    let reloaded = OnboardingStore(defaults: defaults)
    precondition(reloaded.completed && reloaded.draft == store.draft && reloaded.step == .paywall)
    reloaded.edit(.running)
    precondition(reloaded.reviewing && !reloaded.completed)
    let reviewReload = OnboardingStore(defaults: defaults)
    precondition(reviewReload.reviewing && reviewReload.step == .running)
    reviewReload.draft.weeklyDistance = "80"
    precondition(reviewReload.advance() && reviewReload.step == .summary && !reviewReload.reviewing)
    reviewReload.edit(.goals); reviewReload.back()
    precondition(reviewReload.step == .summary)
    reviewReload.edit(.identity); reviewReload.back()
    precondition(reviewReload.step == .summary)
    reviewReload.edit(.balance); precondition(reviewReload.advance() && reviewReload.step == .summary)
    reviewReload.enterApp(); reviewReload.restart()
    precondition(reviewReload.enteredApp && !reviewReload.started && !reviewReload.completed)
    precondition(reviewReload.draft.displayName.isEmpty && reviewReload.step == .identity)
    precondition(defaults.string(forKey: "training") == "keep training history")

    let corrupt = Data("future-or-corrupt-snapshot".utf8)
    defaults.set(corrupt, forKey: key)
    let recovery = OnboardingStore(defaults: defaults)
    precondition(recovery.storageMessage != nil)
    recovery.begin(); recovery.draft.name = "Sample"
    precondition(defaults.data(forKey: key) == corrupt, "Never silently overwrite an unreadable draft")
    recovery.restart()
    precondition(recovery.storageMessage == nil && defaults.data(forKey: key) != corrupt)
    precondition(defaults.string(forKey: "training") == "keep training history")
    precondition(OnboardingMembership.monthly.cents == 1_099)
    precondition(OnboardingMembership.annual.cents == 9_999)
    precondition(OnboardingMembership.annualSavingsPercent == 24)

    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HYBRD_LOCALIZATION_BUNDLE"]!)
    let singular = ["en": "1 day per week", "es": "1 día por semana", "pt-BR": "1 dia por semana", "fr": "1 jour par semaine"]
    for language in L10n.supportedLanguages {
      let bundle = Bundle(url: root.appendingPathComponent(language + ".lproj"))!
      let locale = Locale(identifier: language)
      let one = 1, minutes = 45
      precondition(L10n.text("\(one) days per week", bundle: bundle, locale: locale) == singular[language])
      let rhythm = L10n.text("\(one) lifting days · \(minutes) min per session", bundle: bundle, locale: locale)
      precondition(rhythm.contains("45") && !rhythm.contains("%"), rhythm)
      let savings = L10n.text("Save \(24)%", bundle: bundle, locale: locale)
      precondition(savings.contains("24") && savings.contains("%"), savings)
    }
    print("PASS: onboarding validation, zero/high mileage, exact unit toggles, journey/review/resume, isolated persistence, corruption recovery and USD preview offers")
  }
}
