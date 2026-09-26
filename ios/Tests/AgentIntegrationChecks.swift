import Foundation

@MainActor enum AgentIntegrationChecks {
  static func run() async throws {
    try framing()
    let suite = "hybrd.agent.tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let credential = BackendSession.Credential(token: "fixture-token", user: .init(id: "fixture-user", email: "fixture@example.test", name: "Fixture", emailVerified: true))
    let env = try BackendEnvironment(origin: "https://fixture.example", apiVersion: "v2")
    let scope = try BackendAccountScope(origin: env.origin, athleteID: UUID(), apiVersion: "v2")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let device = UUID()
    var requests: [URLRequest] = []
    var loseResponse = true, cancelled = false, accountValid = true, stale = false
    var inspectJournal: (() throws -> Void)?
    var response = try JSONDecoder().decode(BackendWire.AgentRun.self, from: Data(contentsOf: URL(fileURLWithPath: "../contracts/examples/agent-run-succeeded.json")))
    response.task = .chat; response.status = .queued; response.artifact = nil
    response.lastEventId = try BackendRevision("9007199254740993")
    let capabilities = Data(#"{"schemaVersion":1,"enabled":true,"configured":true,"tasks":{"chat":true,"analyze_workout":true,"create_plan":false,"modify_plan":false},"transport":"sse","memory":"manual","requiresConsent":true,"requiredEntitlement":"pro","maxGenerativeCalls":4,"eventRetentionDays":7}"#.utf8)
    let session = BackendSession(defaults: defaults, send: { request in
      requests.append(request)
      let url = request.url!
      let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
      if url.path.hasSuffix("get-session") { return (try JSONEncoder().encode(["user":credential.user]), http) }
      precondition(url.path.hasPrefix("/v2/agent/"), "Environment and version must propagate to AI requests")
      precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
      if url.path.hasSuffix("capabilities") { return (capabilities, http) }
      if url.path.hasSuffix("/runs") {
        try inspectJournal?()
        if loseResponse { loseResponse = false; throw URLError(.networkConnectionLost) }
        return (try JSONEncoder().encode(response), http)
      }
      if url.path.hasSuffix("/cancel") { cancelled = true }
      var final = response; final.status = cancelled ? .cancelled : .succeeded; final.artifactStale = stale
      return (try JSONEncoder().encode(final), http)
    }, load: { _ in credential }, save: { _,_ in })
    try session.configure(env); try await session.restore()
    let check = { guard accountValid && session.authenticated else { throw BackendContractError.accountChanged } }
    func make() throws -> AgentRunStore {
      try AgentRunStore(directory: directory, scope: scope, deviceID: device, session: session, assertAccount: check, beforeSend: check)
    }
    var coach = try make()
    await coach.refresh()
    inspectJournal = {
      let disk = try make()
      precondition(disk.pending?.body == requests.last?.httpBody, "Save exact bytes before POST")
    }
    await coach.start("Explain my training week")
    try await settle { coach.error != nil }
    precondition(coach.pending != nil && coach.snapshot.entries.count == 1)
    let first = requests.last { $0.url?.path.hasSuffix("/runs") == true }!
    coach.suspend()
    coach = try make()
    precondition(coach.snapshot.entries.count == 1 && coach.pending != nil)
    coach.resume()
    try await settle { coach.pending == nil }
    let posts = requests.filter { $0.url?.path.hasSuffix("/runs") == true }
    precondition(posts.count == 2 && posts[0].httpBody == posts[1].httpBody)
    precondition(first.value(forHTTPHeaderField: "Idempotency-Key") == posts[1].value(forHTTPHeaderField: "Idempotency-Key"))
    precondition(coach.snapshot.entries[0].cursor.rawValue == "9007199254740993")
    precondition(coach.snapshot.threadID == response.threadId)
    let otherScope = try BackendAccountScope(origin: env.origin, athleteID: UUID(), apiVersion: "v2")
    let other = try AgentRunStore(directory: directory, scope: otherScope, deviceID: device, session: session, assertAccount: check, beforeSend: check)
    precondition(other.snapshot.entries.isEmpty)
    await coach.refresh(); loseResponse = true
    await coach.start("Another question")
    try await settle { coach.error != nil }
    let postsBeforeCancel = requests.filter { $0.url?.path.hasSuffix("/runs") == true }.count
    coach.cancel()
    try await Task.sleep(for: .milliseconds(20))
    precondition(requests.filter { $0.url?.path.hasSuffix("/runs") == true }.count == postsBeforeCancel, "Cancelling an unknown run must never create new provider work")
    coach.suspend()
    // Simulate a durable 202 acknowledgement, then cancel without another create request.
    var known = coach.snapshot
    known.entries[known.entries.count - 1].run = response
    try OnboardingAPIClient.encode(known).write(to: OnboardingRequestJournal(directory: directory, scope: scope).file, options: .atomic)
    coach = try make()
    coach.cancel()
    try await settle { coach.pending == nil }
    precondition(cancelled && coach.snapshot.entries.last?.run?.status == .cancelled)
    let before = requests.count
    accountValid = false
    await coach.start("Do not send this after switching accounts")
    precondition(requests.count == before)
    precondition(AgentRunStore.Entry.terminal(.indeterminate))
    coach.suspend()
    print("PASS: AI journal-before-send, lost-response exact retry, cancellation recovery, account/API isolation, bigint cursors and bounded fragmented SSE")
  }
  private static func settle(_ done: () -> Bool) async throws {
    for _ in 0..<200 {
      if done() { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    preconditionFailure("Asynchronous fixture did not settle")
  }
  private static func framing() throws {
    var parser = AgentSSEParser(), frames: [AgentSSEParser.Frame] = []
    let stream = ": ping\r\nevent: heartbeat\r\ndata: {}\r\n\r\nid: 9007199254740993\nevent: status\ndata: élève\ndata: deuxième\n\n"
    for byte in stream.utf8 { if let frame = try parser.consume(byte) { frames.append(frame) } }
    precondition(frames.count == 2 && frames[0].id == nil)
    precondition(frames[1].id == "9007199254740993" && frames[1].data == "élève\ndeuxième")
    do { for _ in 0...65_536 { _ = try parser.consume(65) }; preconditionFailure("Unbounded SSE line") } catch {}
    let result = try JSONDecoder().decode(BackendWire.AgentRun.self, from: Data(contentsOf: URL(fileURLWithPath: "../contracts/examples/agent-run-succeeded.json")))
    precondition(result.artifact?.observations[0].metricRefs.count == 1 && result.artifact?.analyzedResult?.revision.rawValue == "1")
  }
}
