import Foundation

struct BackendAccountScope: Codable, Equatable, Sendable {
  let origin: URL
  let athleteID: UUID

  init(origin: URL, athleteID: UUID) throws {
    guard let c = URLComponents(url: origin, resolvingAgainstBaseURL: false),
          c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
          c.path.isEmpty || c.path == "/", let host = c.host, !host.isEmpty else {
      throw BackendContractError.invalidOrigin
    }
    var allowed = c.scheme == "https"
    #if DEBUG
    // Local debug only. Device/LAN testing requires a deliberately configured HTTPS origin.
    allowed = allowed || (c.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host))
    #endif
    guard allowed else { throw BackendContractError.invalidOrigin }
    var normalized = c; normalized.path = ""; normalized.host = host.lowercased()
    self.origin = normalized.url!; self.athleteID = athleteID
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(origin: c.decode(URL.self, forKey: .origin), athleteID: c.decode(UUID.self, forKey: .athleteID))
  }
}
