import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class CompanionBridge: NSObject, WCSessionDelegate {
  private(set) var snapshot: CompanionSnapshot?
  private(set) var connectionMessage = "Waiting for iPhone"
  private var pending: Data?
  private(set) var receivedRuns: [RunRecording] = []
  private(set) var queuedRunCount = 0
  @ObservationIgnored var onRunReceived: ((RunRecording) -> Bool)?


  override init() {
    super.init()
    receivedRuns = RunArchive.load("inbox")
    queuedRunCount = RunArchive.load("outbox").count
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
      else { self.sendPending(); self.retryTransfers() }
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

  /// The application-level receipt is sent only after the iPhone transaction is durable.
  @discardableResult func queueRun(_ run: RunRecording) -> Bool {
    guard run.isFinished, run.canSave else { return false }
    do {
      _ = try RunArchive.save(run, in: "outbox")
      queuedRunCount = RunArchive.load("outbox").count
      retryTransfers()
      connectionMessage = "Run saved on Watch · transfer queued"
      return true
    } catch { connectionMessage = "Couldn’t save the transfer. Your run remains in the recorder."; return false }
  }
  func retryTransfers() {
    guard WCSession.default.activationState == .activated else { return }
    #if os(watchOS)
    for run in RunArchive.load("outbox") {
      guard !WCSession.default.outstandingFileTransfers.contains(where: { $0.file.metadata?["runID"] as? String == run.id.uuidString }),
        let url = try? RunArchive.directory("outbox").appendingPathComponent(run.id.uuidString + ".json") else { continue }
      WCSession.default.transferFile(url, metadata: ["runID": run.id.uuidString])
    }
    #else
    for run in receivedRuns {
      if onRunReceived?(run) == true { acknowledge(run) }
    }
    #endif
  }
  func acknowledge(_ run: RunRecording) {
    do {
      try RunArchive.remove(run.id.uuidString, from: "inbox")
      receivedRuns.removeAll { $0.id == run.id }
      if WCSession.default.activationState == .activated {
        WCSession.default.transferUserInfo(["runReceipt": run.id.uuidString])
      }
    } catch { connectionMessage = "Saved run; receipt will retry." }
  }
  nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
    // WC owns this temporary URL and removes it after the callback returns.
    guard let data = try? Data(contentsOf: file.fileURL),
      data.count <= 20_000_000,
      let run = try? JSONDecoder().decode(RunRecording.self, from: data), run.isFinished, run.canSave else { return }
    do { _ = try RunArchive.save(run, in: "inbox") } catch { return }
    Task { @MainActor in
      self.receivedRuns = RunArchive.load("inbox")
      self.connectionMessage = "Run received from Apple Watch"
      self.retryTransfers()
    }
  }
  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    guard let id = userInfo["runReceipt"] as? String, UUID(uuidString: id) != nil else { return }
    Task { @MainActor in
      do {
        try RunArchive.remove(id, from: "outbox")
        self.queuedRunCount = RunArchive.load("outbox").count
        self.connectionMessage = "Run saved on iPhone"
      } catch { self.connectionMessage = "Receipt cleanup will retry" }
    }
  }
  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor in self.retryTransfers() }
  }
  nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
    Task { @MainActor in
      if error != nil { self.connectionMessage = "Run is safe on Watch. Transfer will retry." }
      else { self.connectionMessage = "Run delivered · awaiting iPhone save" }
    }
  }

  #if os(iOS)
  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
  nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  #endif
}
