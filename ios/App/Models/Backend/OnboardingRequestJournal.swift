import Foundation
import CryptoKit

/// No tokens are persisted here. Each environment/athlete has a separate atomic file.
struct OnboardingRequestJournal {
  let scope: BackendAccountScope
  let file: URL

  init(directory: URL, scope: BackendAccountScope) {
    self.scope = scope
    let digest = SHA256.hash(data: Data(scope.origin.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    file = directory.appendingPathComponent("\(digest)-\(scope.athleteID.uuidString).json")
  }
  func load() throws -> Snapshot {
    guard FileManager.default.fileExists(atPath: file.path) else { return Snapshot(scope: scope) }
    let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
    guard snapshot.version == 1, snapshot.scope == scope else { throw BackendContractError.accountChanged }
    return snapshot
  }
  func save(_ snapshot: Snapshot) throws {
    guard snapshot.scope == scope else { throw BackendContractError.accountChanged }
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    var options: Data.WritingOptions = [.atomic]
    #if os(iOS)
    options.insert(.completeFileProtection)
    #endif
    try OnboardingAPIClient.encode(snapshot).write(to: file, options: options)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    var url = file; var values = URLResourceValues(); values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }
  struct Snapshot: Codable {
    var version = 1
    var scope: BackendAccountScope
    var remote: BackendWire.OnboardingState?
    var pending: Pending?
  }
  struct Pending: Codable, Equatable {
    enum Kind: String, Codable { case save, complete }
    let key: UUID
    let kind: Kind
    let body: Data
  }
}
