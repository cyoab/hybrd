import Foundation

@MainActor enum BackendConnectionChecks {
  static func run() async throws {
    let env = try BackendEnvironment(origin: "https://TEST.example/", apiVersion: "v2", authPath: "/identity/auth")
    precondition(env.domainURL("bootstrap").absoluteString == "https://test.example/v2/bootstrap")
    precondition(env.authURL("methods").path == "/identity/auth/methods")
    for address in ["https://user:secret@example.com", "https://example.com/path", "https://example.com?token=x", "http://example.com"] {
      do { _ = try BackendEnvironment(origin: address); preconditionFailure("Invalid origin accepted") } catch {}
    }
    for version in ["v0", "../v1", "v1?token=x", "/v1"] {
      do { _ = try BackendEnvironment(origin: "https://example.com", apiVersion: version); preconditionFailure("Invalid version accepted") } catch {}
    }
    let suite = "hybrd.connection-tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var credential: BackendSession.Credential?
    var captured: [URLRequest] = []
    var status = 200
    var responseBody = Data()
    let user = #"{"id":"auth-user","email":"tester@example.test","name":"Tester","emailVerified":true}"#
    let session = BackendSession(defaults: defaults, send: { request in
      captured.append(request)
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: status == 429 ? ["Retry-After":"125"] : [:])!
      return (responseBody, response)
    }, load: { _ in credential }, save: { c, _ in credential = c })
    try session.configure(env)
    responseBody = Data(#"{"emailOtp":true,"otp":{"length":6,"expiresInSeconds":600,"resendAfterSeconds":60}}"#.utf8)
    try await session.discover()
    responseBody = Data(#"{"success":true}"#.utf8)
    try await session.sendCode(to: " Tester@example.test ")
    precondition(session.email == "tester@example.test" && captured.last?.value(forHTTPHeaderField: "Authorization") == nil)
    responseBody = Data(("{\"token\":\"opaque-test-session\",\"user\":" + user + "}").utf8)
    try await session.verify("012345")
    let sent = try JSONSerialization.jsonObject(with: captured.last!.httpBody!) as! [String: String]
    precondition(sent["otp"] == "012345" && credential?.token == "opaque-test-session")
    responseBody = Data(#"{"error":{"code":"UNAUTHORIZED"}}"#.utf8); status = 401
    do { let _: BackendWire.Bootstrap = try await session.domain("bootstrap"); preconditionFailure() } catch {}
    precondition(!session.authenticated && credential == nil)
    precondition(captured.last?.url?.path == "/v2/bootstrap")
    precondition(captured.last?.value(forHTTPHeaderField: "Authorization") == "Bearer opaque-test-session")
    precondition(captured.last?.value(forHTTPHeaderField: "Origin") == nil)
    status = 200; responseBody = Data(#"{"emailOtp":true,"otp":{"length":6,"expiresInSeconds":600,"resendAfterSeconds":60}}"#.utf8)
    try await session.discover()
    status = 429; responseBody = Data(#"{"code":"RATE_LIMITED","message":"Sensitive provider details"}"#.utf8)
    do { try await session.sendCode(to: "second@example.test"); preconditionFailure() }
    catch let error as BackendAPIError { precondition(error.retryAfterSeconds == 125 && error.code == "RATE_LIMITED") }
    let count = captured.count
    do { try await session.sendCode(to: "second@example.test"); preconditionFailure() } catch {}
    precondition(captured.count == count)
    try await replicaRecovery()
    print("PASS: backend environment/version validation, leading-zero OTP, bearer routing, session expiry, cooldown and durable sync recovery")
  }
  private static func replicaRecovery() async throws {
    let env = try BackendEnvironment(origin: "https://sync.example")
    let suite = "hybrd.replica-tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let credential = BackendSession.Credential(token: "test", user: .init(id: "user", email: "x@example.test", name: "X", emailVerified: true))
    var pushBodies: [Data] = [], loseResponse = true, unknownEntity = false
    var assertCommitted: (() throws -> Void)?
    let session = BackendSession(defaults: defaults, send: { request in
      let response = HTTPURLResponse(url: request.url!, statusCode: request.url!.path.hasSuffix("ack") ? 204 : 200, httpVersion: nil, headerFields: nil)!
      if request.url!.path.hasSuffix("get-session") { return (try JSONEncoder().encode(["user": credential.user]), response) }
      if request.url!.path.hasSuffix("push") {
        pushBodies.append(request.httpBody!)
        if loseResponse { loseResponse = false; throw URLError(.networkConnectionLost) }
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let mutation = (body["mutations"] as! [[String: Any]])[0]
        let json: [String: Any] = ["results": [["mutationId": mutation["id"]!, "status":"applied", "entityRevision":"1"]], "serverSequence":"999"]
        return (try JSONSerialization.data(withJSONObject: json), response)
      }
      if request.url!.path.hasSuffix("ack") { try assertCommitted?(); return (Data(), response) }
      let body = unknownEntity ? #"{"changes":[{"entityType":"future_entity"}],"nextCursor":"7","hasMore":false}"# : #"{"changes":[],"nextCursor":"0","hasMore":false}"#
      return (Data(body.utf8), response)
    }, load: { _ in credential }, save: { _,_ in })
    try session.configure(env); try await session.restore()
    let scope = try BackendAccountScope(origin: env.origin, athleteID: UUID())
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let accountCheck = { guard session.authenticated else { throw BackendContractError.accountChanged } }
    var replica = try BackendReplica(directory: dir, scope: scope, assertAccount: accountCheck)
    let mutation = try BackendMutation(.athlete, id: scope.athleteID, operation: .update, revision: BackendRevision("1"), payload: ["timezone":"UTC"])
    try replica.enqueue([mutation], local: TrainingState.sample())
    do { try await replica.sync(session: session); preconditionFailure() } catch {}
    let device = replica.snapshot.deviceID
    replica = try BackendReplica(directory: dir, scope: scope, assertAccount: accountCheck)
    precondition(replica.snapshot.deviceID == device && replica.snapshot.outbox.first?.id == mutation.id)
    assertCommitted = { let persisted = try BackendReplica(directory: dir, scope: scope, assertAccount: accountCheck); precondition(persisted.snapshot.outbox.isEmpty && persisted.snapshot.cursor.rawValue == "0") }
    try await replica.sync(session: session)
    precondition(pushBodies.count == 2 && pushBodies[0] == pushBodies[1])
    precondition(replica.snapshot.cursor.rawValue == "0") // Never use the push's 999 hint.
    unknownEntity = true
    do { try await replica.sync(session: session); preconditionFailure() } catch {}
    precondition(replica.snapshot.cursor.rawValue == "0")
  }
}
