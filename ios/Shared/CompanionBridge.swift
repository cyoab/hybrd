import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class CompanionBridge: NSObject, WCSessionDelegate {
  private(set) var snapshot: CompanionSnapshot?
  private(set) var connectionMessage = "Waiting for iPhone"
  private var pending: Data?

  override init() {
    super.init()
    if let data = UserDefaults.standard.data(forKey: "companion.snapshot") {
      snapshot = try? JSONDecoder().decode(CompanionSnapshot.self, from: data)
    }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  func publish(_ value: CompanionSnapshot) {
    snapshot = value
    pending = try? JSONEncoder().encode(value)
    sendPending()
  }

  private func sendPending() {
    guard let pending, WCSession.default.activationState == .activated else { return }
    #if os(iOS)
    guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else {
      connectionMessage = "Install hybrd on your paired Apple Watch"
      return
    }
    #endif
    do {
      try WCSession.default.updateApplicationContext(["snapshot": pending])
      connectionMessage = "Plan queued for Apple Watch"
    } catch {
      connectionMessage = "Watch transfer will retry when connected"
    }
  }

  nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    Task { @MainActor in
      if let error { self.connectionMessage = error.localizedDescription }
      else { self.sendPending() }
      if let data = session.receivedApplicationContext["snapshot"] as? Data { self.receive(data) }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    guard let data = applicationContext["snapshot"] as? Data else { return }
    Task { @MainActor in self.receive(data) }
  }

  private func receive(_ data: Data) {
    guard let decoded = try? JSONDecoder().decode(CompanionSnapshot.self, from: data) else { return }
    snapshot = decoded
    UserDefaults.standard.set(data, forKey: "companion.snapshot")
    connectionMessage = "Plan received"
  }

  #if os(iOS)
  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
  nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  #endif
}
