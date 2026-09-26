import Foundation
import Observation

@MainActor @Observable final class BackendSession {
  struct User: Codable, Equatable { var id: String; var email: String; var name: String; var emailVerified: Bool }
  struct Credential: Codable { var token: String; var user: User }
  struct Methods: Decodable {
    var emailOtp: Bool
    var otp: Timing
    struct Timing: Decodable { var length: Int; var expiresInSeconds: Int; var resendAfterSeconds: Int }
  }
  struct Success: Decodable { var success: Bool }
  private(set) var environment: BackendEnvironment?
  private(set) var credential: Credential?
  private(set) var methods: Methods?
  private(set) var email = ""
  private(set) var codeSent = false
  private(set) var resendAt = Date.distantPast
  private(set) var isWorking = false
  private(set) var authenticated = false
  var message: String?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let send: OnboardingAPIClient.Send
  @ObservationIgnored private let loadCredential: (BackendEnvironment) throws -> Credential?
  @ObservationIgnored private let saveCredential: (Credential?, BackendEnvironment) throws -> Void
  init(defaults: UserDefaults = .standard, send: OnboardingAPIClient.Send? = nil,
       load: ((BackendEnvironment) throws -> Credential?)? = nil,
       save: ((Credential?, BackendEnvironment) throws -> Void)? = nil) {
    self.defaults = defaults
    self.send = send ?? { try await OnboardingHTTPTransport.shared.send($0) }
    self.loadCredential = load ?? { try BackendCredentialVault().read(environment: $0) }
    self.saveCredential = save ?? { try BackendCredentialVault().write($0, environment: $1) }
    if let data = defaults.data(forKey: "hybrd.backend.environment") {
      do { environment = try JSONDecoder().decode(BackendEnvironment.self, from: data) }
      catch { message = L10n.text("Check your backend connection settings.") }
    }
  }
  func configure(_ value: BackendEnvironment) throws {
    guard !isWorking, credential == nil else { throw BackendContractError.requestInFlight }
    defaults.set(try JSONEncoder().encode(value), forKey: "hybrd.backend.environment")
    generation = UUID(); environment = value; methods = nil; codeSent = false; message = nil
  }
  func discover() async throws {
    guard let environment else { throw BackendContractError.invalidOrigin }
    methods = try await request(environment.authURL("methods"), method: "GET", authorized: false)
  }
  func checkServer() async throws {
    guard let environment else { throw BackendContractError.invalidOrigin }
    let _: BackendNoContent = try await request(environment.origin.appendingPathComponent("health/ready"), method: "GET", authorized: false)
    struct Contract: Decodable { var paths: [String: BackendJSONValue] }
    let contract: Contract = try await request(environment.origin.appendingPathComponent("openapi.json"), method: "GET", authorized: false)
    guard contract.paths["/" + environment.apiVersion + "/bootstrap"] != nil else { throw BackendContractError.unexpectedValue }
    try await discover()
  }
  func restore() async throws {
    guard let environment else { return }
    credential = try loadCredential(environment)
    guard credential != nil else { return }
    authenticated = true // Permit only this cached account during a transient offline restore.
    struct Active: Decodable { var user: User }
    let active: Active? = try await request(environment.authURL("get-session"), method: "GET")
    guard let active else { try clear(); return }
    guard credential?.user.id == active.user.id else { try clear(); throw BackendContractError.accountChanged }
    authenticated = true
  }
  func sendCode(to input: String) async throws {
    guard !isWorking else { throw BackendContractError.requestInFlight }
    guard let environment, methods?.emailOtp == true else { throw BackendContractError.emailUnavailable }
    let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalized.count <= 254, normalized.contains("@"), !normalized.contains(where: \.isWhitespace) else { throw BackendContractError.invalidEmail }
    let cooldownKey = "hybrd.otp.cooldown." + environment.storageID + "." + normalized
    let deadline = defaults.object(forKey: cooldownKey) as? Date ?? .distantPast
    resendAt = deadline
    guard Date() >= deadline else { throw BackendContractError.cooldown }
    isWorking = true; defer { isWorking = false }
    struct Body: Encodable { var email: String; var type = "sign-in" }
    do {
      let result: Success = try await request(environment.authURL("email-otp/send-verification-otp"), method: "POST", body: Body(email: normalized), authorized: false)
      guard result.success else { throw BackendContractError.invalidResponse }
      email = normalized; codeSent = true
      resendAt = Date().addingTimeInterval(Double(methods?.otp.resendAfterSeconds ?? 60))
      defaults.set(resendAt, forKey: cooldownKey)
    } catch {
      if let delay = (error as? BackendAPIError)?.retryAfterSeconds {
        resendAt = Date().addingTimeInterval(delay); defaults.set(resendAt, forKey: cooldownKey)
      }
      throw error
    }
  }
  func verify(_ code: String) async throws {
    guard !isWorking, codeSent, let environment else { throw BackendContractError.restoreRequired }
    guard code.count == methods?.otp.length, code.utf8.allSatisfy({ (48...57).contains($0) }) else { throw BackendContractError.invalidCode }
    isWorking = true; defer { isWorking = false }
    struct Body: Encodable { var email: String; var otp: String }
    let result: Credential = try await request(environment.authURL("sign-in/email-otp"), method: "POST", body: Body(email: email, otp: code), authorized: false)
    guard !result.token.isEmpty, result.user.emailVerified else { throw BackendContractError.invalidResponse }
    try saveCredential(result, environment); credential = result; authenticated = true; generation = UUID()
  }
  func resumeCode(for input: String) throws {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard value.contains("@"), !value.contains(where: \.isWhitespace), value.count <= 254 else { throw BackendContractError.invalidEmail }
    email = value; codeSent = true
  }
  func editEmail() { codeSent = false }
  func signOut() async throws {
    guard !isWorking, let environment else { throw BackendContractError.requestInFlight }
    isWorking = true; defer { isWorking = false }
    let _: Success = try await request(environment.authURL("sign-out"), method: "POST", body: [String:String]())
    try clear()
  }
  /// Explicit local sign-out retains account-scoped pending work; server revocation may still be needed.
  func clear() throws {
    if let environment { try saveCredential(nil, environment) }
    generation = UUID(); credential = nil; authenticated = false; codeSent = false
  }
  func rotate(_ token: String) throws {
    guard var value = credential, let environment else { throw BackendContractError.accountChanged }
    value.token = token; try saveCredential(value, environment); credential = value
  }
  func domain<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = [], headers: [String: String] = [:]) async throws -> T {
    guard let environment else { throw BackendContractError.invalidOrigin }
    return try await perform(environment.domainURL(path, query: query), method: method, body: body, authorized: true, headers: headers)
  }
  func request<T: Decodable>(_ url: URL, method: String, authorized: Bool = true) async throws -> T {
    try await perform(url, method: method, body: nil, authorized: authorized)
  }
  func request<T: Decodable, B: Encodable>(_ url: URL, method: String, body: B, authorized: Bool = true) async throws -> T {
    try await perform(url, method: method, body: OnboardingAPIClient.encode(body), authorized: authorized)
  }
  struct ProgressResponse {
    var key: String
    var value: BackendWire.ProgressSummary
    var etag: String?
  }
  func progressSummary(days: Int, timezone: String, previous: ProgressResponse?) async throws -> ProgressResponse {
    guard let environment, let credential else { throw BackendContractError.restoreRequired }
    let key = environment.storageID + "|" + credential.user.id + "|" + String(days) + "|" + timezone
    let cached = previous?.key == key ? previous : nil
    let url = environment.domainURL("progress/summary", query: [.init(name: "periodDays", value: String(days)), .init(name: "timezone", value: timezone)])
    let (data, response) = try await exchange(url, method: "GET", body: nil, authorized: true, etag: cached?.etag)
    if response.statusCode == 304 {
      guard let cached else { throw BackendContractError.invalidResponse }; return cached
    }
    return ProgressResponse(key: key, value: try JSONDecoder().decode(BackendWire.ProgressSummary.self, from: data), etag: response.value(forHTTPHeaderField: "ETag"))
  }
  /// Streams only this authenticated origin. Re-check identity before every delivered frame.
  func agentEvents(runID: UUID, after cursor: BackendRevision, receive: @MainActor (AgentStreamEvent) throws -> Void) async throws {
    guard let environment, let credential else { throw BackendContractError.restoreRequired }
    let expected = generation
    var request = URLRequest(url: environment.domainURL("agent/runs/" + runID.uuidString.lowercased() + "/events"))
    request.setValue("Bearer " + credential.token, forHTTPHeaderField: "Authorization")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue(cursor.rawValue, forHTTPHeaderField: "Last-Event-ID")
    let (bytes, response) = try await OnboardingHTTPTransport.shared.bytes(request)
    defer { bytes.task.cancel() }
    guard expected == generation else { throw BackendContractError.accountChanged }
    if response.statusCode == 401 { try clear(); throw BackendContractError.restoreRequired }
    guard response.statusCode == 200,
      response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else {
      throw BackendAPIError.from(response, data: Data())
    }
    if let token = response.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty { try rotate(token) }
    var parser = AgentSSEParser(), total = 0
    for try await byte in bytes {
      try Task.checkCancellation()
      guard expected == generation else { throw BackendContractError.accountChanged }
      total += 1
      guard total <= 4_000_000 else { throw BackendContractError.invalidResponse }
      if let frame = try parser.consume(byte) {
        if frame.event == "error" { throw BackendContractError.invalidResponse }
        guard let id = frame.id, frame.event != "heartbeat" else { continue }
        let event = try JSONDecoder().decode(AgentStreamEvent.self, from: Data(frame.data.utf8))
        guard event.id.rawValue == id, event.runId == runID, event.type.rawValue == frame.event else { throw BackendContractError.invalidResponse }
        try receive(event)
      }
    }
  }
  private func perform<T: Decodable>(_ url: URL, method: String, body: Data?, authorized: Bool, headers: [String: String] = [:]) async throws -> T {
    let (data, response) = try await exchange(url, method: method, body: body, authorized: authorized, headers: headers)
    return try JSONDecoder().decode(T.self, from: response.statusCode == 204 ? Data("{}".utf8) : data)
  }
  private func exchange(_ url: URL, method: String, body: Data?, authorized: Bool, etag: String? = nil, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
    let expected = generation
    guard url.host == environment?.origin.host, url.port == environment?.origin.port,
          url.scheme == environment?.origin.scheme else { throw BackendContractError.invalidOrigin }
    var r = URLRequest(url: url); r.httpMethod = method; r.httpBody = body
    r.setValue("application/json", forHTTPHeaderField: "Accept")
    for (key, value) in headers { r.setValue(value, forHTTPHeaderField: key) }
    if let etag { r.setValue(etag, forHTTPHeaderField: "If-None-Match") }
    if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    if authorized {
      guard let credential else { throw BackendContractError.restoreRequired }
      r.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
    }
    let (data, response) = try await send(r)
    guard generation == expected else { throw BackendContractError.accountChanged }; try Task.checkCancellation()
    if authorized, let token = response.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty { try rotate(token) }
    if response.statusCode == 401, authorized { try clear() }
    guard (200..<300).contains(response.statusCode) || (response.statusCode == 304 && etag != nil) else { throw BackendAPIError.from(response, data: data) }
    return (data, response)
  }
}
