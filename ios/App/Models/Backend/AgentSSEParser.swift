import Foundation

/// Bounded UTF-8 SSE framing, independent of arbitrary network chunk boundaries.
struct AgentSSEParser {
  struct Frame: Equatable { var id: String?; var event: String; var data: String }
  private var line: [UInt8] = []
  private var id: String?
  private var event = "message"
  private var data: [String] = []
  private var size = 0
  mutating func consume(_ byte: UInt8) throws -> Frame? {
    guard size < 65_536 else { throw BackendContractError.invalidResponse }
    size += 1
    if byte != 10 { line.append(byte); return nil }
    if line.last == 13 { line.removeLast() }
    guard let text = String(bytes: line, encoding: .utf8) else { throw BackendContractError.invalidResponse }
    line = []
    if text.isEmpty {
      let frame = data.isEmpty ? nil : Frame(id: id, event: event, data: data.joined(separator: "\n"))
      id = nil; event = "message"; data = []; size = 0
      return frame
    }
    if text.hasPrefix(":") { return nil }
    let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    var value = parts.count == 2 ? String(parts[1]) : ""
    if value.hasPrefix(" ") { value.removeFirst() }
    switch parts[0] {
    case "id": if !value.contains("\0") { id = value }
    case "event": event = value
    case "data": data.append(value)
    default: break
    }
    return nil
  }
}

/// The SSE payload is documented by /agent/runs/{id}/events; keep IDs separate from sync cursors.
struct AgentStreamEvent: Decodable {
  enum Kind: String, Decodable { case status, toolStatus = "tool_status", artifactReady = "artifact_ready", completed, failed, cancelled }
  struct Detail: Decodable { var status: BackendWire.AgentRunStatus?; var tool: String?; var errorCode: String? }
  var id: BackendRevision
  var runId: UUID
  var type: Kind
  var data: Detail
  var createdAt: BackendInstant
}
