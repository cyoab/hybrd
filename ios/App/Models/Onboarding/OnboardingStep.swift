import Foundation

enum OnboardingStep: Int, CaseIterable, Codable, Identifiable {
  case identity, goals, balance, running, strength, body, rhythm, equipment, focus, readiness, connections, summary, paywall
  var id: Int { rawValue }
  var chapter: String {
    switch self {
    case .identity, .goals, .balance: L10n.text("Your direction")
    case .running, .strength, .body: L10n.text("Your starting point")
    case .rhythm, .equipment, .focus, .readiness, .connections: L10n.text("Your real life")
    case .summary, .paywall: L10n.text("Your next chapter")
    }
  }
  var title: String {
    switch self {
    case .identity: L10n.text("First, what should we call you?")
    case .goals: L10n.text("What are you working toward?")
    case .balance: L10n.text("Two disciplines. Your balance.")
    case .running: L10n.text("Where is your running today?")
    case .strength: L10n.text("And your strength training?")
    case .body: L10n.text("A little more about you.")
    case .rhythm: L10n.text("Make room for progress.")
    case .equipment: L10n.text("Your gym. Your possibilities.")
    case .focus: L10n.text("Where would you like to grow?")
    case .readiness: L10n.text("How are you feeling coming in?")
    case .connections: L10n.text("Bring your story with you.")
    case .summary: L10n.text("This is your starting line.")
    case .paywall: L10n.text("One membership. All of you.")
    }
  }
  var detail: String {
    switch self {
    case .identity: L10n.text("We’ll get to know the athlete behind the numbers. One small step at a time.")
    case .goals: L10n.text("Choose a direction for each discipline. You can always change it as you grow.")
    case .balance: L10n.text("When life gets busy, which goal should your training protect first?")
    case .running: L10n.text("Your recent routine matters more than your best-ever week. Zero is a valid starting point.")
    case .strength: L10n.text("Your running and lifting experience can be completely different. We’ll treat them that way.")
    case .body: L10n.text("These details are optional. Share what you’re comfortable with, or add them later.")
    case .rhythm: L10n.text("Choose the days that fit your life. Rest belongs in the plan, too.")
    case .equipment: L10n.text("Start with a setup, then adjust what you actually have access to.")
    case .focus: L10n.text("Choose a few priorities, or keep a balanced focus by leaving these unselected.")
    case .readiness: L10n.text("There’s no perfect starting point. Tell us what a sustainable start looks like for you.")
    case .connections: L10n.text("Choose what you’d like to connect later. You’ll review any imported data before using it.")
    case .summary: L10n.text("A reflection of what you told us. Tap any section to make it more you.")
    case .paywall: L10n.text("Running and strength, moving in the same direction.")
    }
  }
}
