import Foundation
import CryptoKit

/// Domain API version and auth base path are intentionally independent.
struct BackendEnvironment: Codable, Equatable, Sendable {
  let origin: URL
  let apiVersion: String
  let authPath: String
  init(origin: String, apiVersion: String = "v1", authPath: String = "/api/auth") throws {
    guard let url = URL(string: origin.trimmingCharacters(in: .whitespacesAndNewlines)),
          apiVersion.range(of: "^v[1-9][0-9]*$", options: .regularExpression) != nil,
          authPath.range(of: "^(/[A-Za-z0-9_-]+)+$", options: .regularExpression) != nil else { throw BackendContractError.invalidOrigin }
    self.origin = try BackendAccountScope(origin: url, athleteID: UUID()).origin
    self.apiVersion = apiVersion; self.authPath = authPath
  }
  var storageID: String {
    SHA256.hash(data: Data("\(origin.absoluteString)|\(apiVersion)|\(authPath)".utf8)).map { String(format: "%02x", $0) }.joined()
  }
  func domainURL(_ path: String, query: [URLQueryItem] = []) -> URL {
    url(path: "/\(apiVersion)/" + path, query: query)
  }
  func authURL(_ path: String) -> URL { url(path: authPath + "/" + path) }
  private func url(path: String, query: [URLQueryItem] = []) -> URL {
    var c = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
    c.path = path; c.queryItems = query.isEmpty ? nil : query; return c.url!
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(origin: c.decode(String.self, forKey: .origin), apiVersion: c.decode(String.self, forKey: .apiVersion), authPath: c.decode(String.self, forKey: .authPath))
  }
}
