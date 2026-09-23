import Foundation

enum LocalizationChecks {
  static func run() throws {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HYBRD_LOCALIZATION_BUNDLE"]!)
    let titles = ["en": "Athlete profile", "es": "Perfil del atleta", "pt-BR": "Perfil do atleta", "fr": "Profil de l’athlète"]
    let singles = ["en": "1 personal best", "es": "1 récord personal", "pt-BR": "1 recorde pessoal", "fr": "1 record personnel"]
    let plurals = ["en": "2 personal bests", "es": "2 récords personales", "pt-BR": "2 recordes pessoais", "fr": "2 records personnels"]
    for language in L10n.supportedLanguages {
      let bundle = Bundle(url: root.appendingPathComponent(language + ".lproj"))!
      let locale = Locale(identifier: language)
      precondition(L10n.content("Athlete profile", bundle: bundle) == titles[language])
      let one = 1, two = 2
      precondition(L10n.text("\(one) personal bests", bundle: bundle, locale: locale) == singles[language])
      precondition(L10n.text("\(two) personal bests", bundle: bundle, locale: locale) == plurals[language])
      let summary = L10n.text("\(one) sets × \(two) reps", bundle: bundle, locale: locale)
      let expectedSummary = ["en": "1 set × 2 reps", "es": "1 serie × 2 repeticiones", "pt-BR": "1 série × 2 repetições", "fr": "1 série × 2 répétitions"]
      precondition(summary == expectedSummary[language], summary)
      let swapped = L10n.text("\(two) sets × \(one) reps", bundle: bundle, locale: locale)
      let expectedSwapped = ["en": "2 sets × 1 rep", "es": "2 series × 1 repetición", "pt-BR": "2 séries × 1 repetição", "fr": "2 séries × 1 répétition"]
      precondition(swapped == expectedSwapped[language], swapped)
      let value = L10n.text("Added \("TEST RUN") on \("TEST DATE")", bundle: bundle, locale: locale)
      precondition(value.contains("TEST RUN") && value.contains("TEST DATE") && !value.contains("%@"))
      precondition(language == "en" || !value.hasPrefix("Added"))
      // Unknown/user-authored names pass through, including punctuation that resembles formatting.
      let custom = "Yoab’s 100% workout %@"
      precondition(L10n.content(custom, bundle: bundle) == custom)
      if language != "en" {
        for recipe in RunWorkoutTemplate.allCases {
          for key in [recipe.title, recipe.subtitle, recipe.purpose] + recipe.segments.flatMap({ [$0.title, $0.cue] }) {
            // Tempo is a shared training term in all four languages.
            precondition(key == "Tempo" || L10n.content(key, bundle: bundle) != key, "Missing recipe: \(language) / \(key)")
          }
        }
        for goal in RunningGoal.allCases where goal != .fiveK && goal != .tenK && !(language == "fr" && goal == .marathon) {
          precondition(L10n.content(goal.rawValue, bundle: bundle) != goal.rawValue)
        }
      }
    }
    precondition(Bundle.preferredLocalizations(from: L10n.supportedLanguages, forPreferences: ["es-MX"]).first == "es")
    precondition(Bundle.preferredLocalizations(from: L10n.supportedLanguages, forPreferences: ["pt-BR"]).first == "pt-BR")
    precondition(Bundle.preferredLocalizations(from: L10n.supportedLanguages, forPreferences: ["fr-CA"]).first == "fr")
    precondition(Bundle.preferredLocalizations(from: L10n.supportedLanguages, forPreferences: ["ja"]).first == "en")
    for region in ["es_MX", "pt_BR", "fr_CA"] {
      let locale = Locale(identifier: region)
      let text = 70.5.formatted(.number.grouping(.never).locale(locale))
      precondition(TrainingProfile.parseWeeklyKilometers(text, locale: locale) == 70.5)
      precondition(TrainingWeightUnit.pounds.parse(text, kilograms: 0...1_000, locale: locale) != nil)
    }
    let coachState = TrainingState.sample()
    for prompt in ["Why is my week arranged this way?", "¿Por qué mi semana está organizada así?", "Por que minha semana está organizada assim?", "Pourquoi ma semaine est-elle organisée ainsi ?"] {
      precondition(LocalCoach.reply(to: prompt, state: coachState).hasPrefix("This week"))
    }
    for prompt in ["I’m feeling tired", "Me siento cansado", "Estou cansado", "Je ressens de la fatigue"] {
      precondition(LocalCoach.reply(to: prompt, state: coachState).hasPrefix("You don’t need"))
    }
    for prompt in ["How is my progress?", "¿Cómo va mi progreso?", "Como está meu progresso?", "Comment évolue ma progression ?"] {
      precondition(LocalCoach.reply(to: prompt, state: coachState).hasPrefix("There are no completed"))
    }
    precondition(LocalCoach.reply(to: "J’adore mon plan", state: coachState).hasPrefix("This week"))
    let profile = TrainingProfile()
    let before = try JSONEncoder().encode(profile)
    _ = profile.runningGoal.displayName
    _ = profile.strengthGoal.displayName
    _ = profile.priority.displayName
    let decoded = try JSONDecoder().decode(TrainingProfile.self, from: before)
    precondition(decoded == profile && decoded.runningGoal.rawValue == "Half marathon")
    let plan = SampleTraining.makePlan(profile: profile)
    var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as! [String: Any]
    payload.removeValue(forKey: "change")
    let legacy = try JSONDecoder().decode(TrainingPlan.self, from: JSONSerialization.data(withJSONObject: payload))
    precondition(legacy.change == nil && legacy.workouts == plan.workouts)
    print("PASS: four-language bundle lookups, native singular/plural formatting, interpolation, recipe coverage, regional fallbacks, localized decimal entry and unchanged legacy profile/plan data")
  }
}
