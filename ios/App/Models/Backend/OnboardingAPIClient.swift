import Foundation

/// Account-scoped domain client. Auth/bootstrap/Keychain remain the caller's responsibility.
@MainActor final class OnboardingAPIClient {
  struct Credentials { var scope: BackendAccountScope; var token: String }
  typealias Send = @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)
  let scope: BackendAccountScope
  private let credentials: () throws -> Credentials
  private let rotateToken: (BackendAccountScope, String) throws -> Void
  private let send: Send

  init(scope: BackendAccountScope, credentials: @escaping () throws -> Credentials,
       rotateToken: @escaping (BackendAccountScope, String) throws -> Void, send: Send? = nil) {
    self.scope = scope; self.credentials = credentials; self.rotateToken = rotateToken
    let transport = OnboardingHTTPTransport.shared
    self.send = send ?? { try await transport.send($0) }
  }
  func getOnboarding() async throws -> BackendWire.OnboardingState { try await request(.getOnboarding) }
  func getCatalog() async throws -> BackendWire.ExerciseCatalog { try await request(.getCatalog) }
  func getStrava() async throws -> BackendWire.StravaConnectionStatus { try await request(.getStrava) }
  func connectStrava() async throws -> BackendWire.ConnectStravaResponse {
    try await request(.connectStrava, body: Data(#"{"autoPublish":false}"#.utf8))
  }
  func refreshStrava() async throws -> BackendWire.RefreshStravaResponse { try await request(.refreshStrava, body: Data("{}".utf8)) }

  func save(_ request: BackendWire.SaveOnboardingDraft, key: UUID) async throws -> BackendWire.OnboardingDraftSaved {
    try await self.request(.saveOnboardingDraft, body: Self.encode(request), key: key)
  }
  func complete(_ request: BackendWire.CompleteOnboarding, key: UUID) async throws -> BackendWire.OnboardingCompletionReceipt {
    try await self.request(.completeOnboarding, body: Self.encode(request), key: key)
  }
  // The durable coordinator resends these exact bytes after an unknown outcome.
  func replaySave(body: Data, key: UUID) async throws -> BackendWire.OnboardingDraftSaved {
    _ = try JSONDecoder().decode(BackendWire.SaveOnboardingDraft.self, from: body)
    return try await request(.saveOnboardingDraft, body: body, key: key)
  }
  func replayCompletion(body: Data, key: UUID) async throws -> BackendWire.OnboardingCompletionReceipt {
    _ = try JSONDecoder().decode(BackendWire.CompleteOnboarding.self, from: body)
    return try await request(.completeOnboarding, body: body, key: key)
  }
  nonisolated static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }
  func assertAccount() throws {
    let current = try credentials()
    guard current.scope == scope, !current.token.isEmpty else { throw BackendContractError.accountChanged }
  }
  private func request<T: Decodable>(_ endpoint: OnboardingEndpoint, body: Data? = nil, key: UUID? = nil) async throws -> T {
    try assertAccount()
    var request = URLRequest(url: scope.origin.appendingPathComponent(String(endpoint.path.dropFirst())))
    request.httpMethod = endpoint.method; request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    request.setValue("Bearer \(try credentials().token)", forHTTPHeaderField: "Authorization")
    if let key { request.setValue(key.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key") }
    let (data, response) = try await send(request)
    try assertAccount(); try Task.checkCancellation()
    if let token = response.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty { try rotateToken(scope, token) }
    guard (200..<300).contains(response.statusCode) else { throw BackendAPIError.from(response, data: data) }
    return try JSONDecoder().decode(T.self, from: data)
  }
}
