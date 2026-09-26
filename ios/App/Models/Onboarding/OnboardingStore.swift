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
  @ObservationIgnored private let key: String

  init(defaults: UserDefaults = .standard, key: String = "hybrd.onboarding.preview.v1") {
    self.key = key
    self.defaults = defaults
    if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Snapshot.self, from: data), saved.version == 1 {
      draft = saved.draft; step = saved.step; started = saved.started; completed = saved.completed; enteredApp = saved.enteredApp; reviewing = saved.reviewing ?? false
    } else {
      draft = OnboardingDraft(); step = .identity; started = false; completed = false; enteredApp = false; reviewing = false
      if defaults.data(forKey: key) != nil { storageMessage = L10n.text("Your saved setup could not be opened. Your account data has not been changed.") }
    }
  }
  func restoreConnected(_ value: OnboardingDraft, step: OnboardingStep) {
    draft = value; self.step = step; started = true; reviewing = false; completed = false; enteredApp = false; save()
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
  func leaveApp() { enteredApp = false; save() }
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
    } catch { storageMessage = L10n.text("Your setup couldn’t be saved. Keep this screen open and try again.") }
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
