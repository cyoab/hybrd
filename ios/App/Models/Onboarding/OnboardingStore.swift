import Foundation
import Observation

@MainActor @Observable final class OnboardingStore {
  var draft: OnboardingDraft { didSet { save() } }
  private(set) var step: OnboardingStep
  private(set) var started: Bool
  private(set) var reviewing: Bool
  private(set) var completed: Bool
  private(set) var enteredApp: Bool
  private(set) var storageMessage: String?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let key = "hybrd.onboarding.preview.v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Snapshot.self, from: data), saved.version == 1 {
      draft = saved.draft; step = saved.step; started = saved.started; completed = saved.completed; enteredApp = saved.enteredApp; reviewing = saved.reviewing ?? false
    } else {
      draft = OnboardingDraft(); step = .identity; started = false; completed = false; enteredApp = false; reviewing = false
      if defaults.data(forKey: key) != nil { storageMessage = L10n.text("The saved preview couldn’t be opened. Start again to save a new draft.") }
    }
  }
  func begin() { started = true; completed = false; save() }
  @discardableResult func advance() -> Bool {
    guard draft.validation(for: step) == nil else { return false }
    if reviewing { reviewing = false; step = .summary; save(); return true }
    if let next = OnboardingStep(rawValue: step.rawValue + 1) { step = next; save(); return true }
    return false
  }
  func back() { if reviewing { reviewing = false; step = .summary; save(); return }; if let previous = OnboardingStep(rawValue: step.rawValue - 1) { step = previous; save() } }
  func edit(_ step: OnboardingStep) { self.step = step; reviewing = step.rawValue < OnboardingStep.summary.rawValue; completed = false; save() }
  @discardableResult func finishPreview() -> Bool {
    guard step == .paywall, draft.validation(for: .paywall) == nil else { return false }
    completed = true; save(); return true
  }
  func enterApp() { enteredApp = true; save() }
  func restart() {
    defaults.removeObject(forKey: key)
    storageMessage = nil
    draft = OnboardingDraft(); step = .identity; started = false; completed = false; reviewing = false
    save()
  }
  private func save() {
    guard storageMessage == nil else { return }
    do {
      let snapshot = Snapshot(draft: draft, step: step, started: started, completed: completed, enteredApp: enteredApp, reviewing: reviewing)
      defaults.set(try JSONEncoder().encode(snapshot), forKey: key)
    } catch { storageMessage = L10n.text("Your preview couldn’t be saved. Keep this screen open and try again.") }
  }
  private struct Snapshot: Codable {
    var version = 1
    var draft: OnboardingDraft
    var step: OnboardingStep
    var started: Bool
    var completed: Bool
    var enteredApp: Bool
    var reviewing: Bool?
  }
}
