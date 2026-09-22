import Foundation

/// Atomic local checkpoints and transfer files; no network service or account required.
enum RunArchive {
  static func directory(_ name: String) throws -> URL {
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let url = base.appendingPathComponent("hybrd-runs/" + name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  static func save(_ recording: RunRecording, in folder: String, name: String? = nil) throws -> URL {
    let url = try directory(folder).appendingPathComponent((name ?? recording.id.uuidString) + ".json")
    try JSONEncoder().encode(recording).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    return url
  }
  static var hasCheckpoint: Bool {
    guard let url = try? directory("active").appendingPathComponent("current.json") else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }
  static func loadActive() -> RunRecording? {
    guard var run = load("active").first else { return nil }
    guard let file = try? directory("active").appendingPathComponent(run.id.uuidString + ".route"),
      let data = try? Data(contentsOf: file) else { return run }
    var previous: Date?
    run.route = data.split(separator: 10).compactMap { line in
      guard let point = try? JSONDecoder().decode(RunLocation.self, from: Data(line)),
        point.timestamp <= run.checkpointAt, previous.map({ point.timestamp > $0 }) ?? true else { return nil }
      previous = point.timestamp
      return point
    }
    return run
  }
  static func checkpoint(_ run: RunRecording, points: [RunLocation]) throws {
    let file = try directory("active").appendingPathComponent(run.id.uuidString + ".route")
    if !FileManager.default.fileExists(atPath: file.path) {
      try Data().write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    if !points.isEmpty {
      let handle = try FileHandle(forWritingTo: file)
      defer { try? handle.close() }
      try handle.seekToEnd()
      var data = Data()
      for point in points { data.append(try JSONEncoder().encode(point)); data.append(10) }
      try handle.write(contentsOf: data)
      try handle.synchronize()
    }
    var metadata = run
    metadata.route = []
    _ = try save(metadata, in: "active", name: "current")
  }
  static func removeCheckpoint(_ id: UUID) throws {
    try remove("current", from: "active")
    let file = try directory("active").appendingPathComponent(id.uuidString + ".route")
    if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
  }
  static func load(_ folder: String) -> [RunRecording] {
    guard let url = try? directory(folder), let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return [] }
    return files.filter { $0.pathExtension == "json" }.compactMap { file in
      guard let data = try? Data(contentsOf: file) else { return nil }
      return try? JSONDecoder().decode(RunRecording.self, from: data)
    }.sorted { $0.startedAt < $1.startedAt }
  }
  static func remove(_ id: String, from folder: String) throws {
    let url = try directory(folder).appendingPathComponent(id + ".json")
    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
  }
}
