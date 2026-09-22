import Foundation

/// Expands prescriptions into their chronological order; never represents recorded activity.
struct RunTimeline {
  var steps: [Step] = []

  var totalSeconds: Int { steps.last?.endSeconds ?? 0 }

  init(segments: [RunSegment]) {
    var index = 0
    var elapsed = 0
    while index < segments.count {
      let segment = segments[index]
      let recovery = Self.pairedRecovery(after: index, in: segments)
      for repetition in 1...max(1, segment.repetitions ?? 1) {
        for part in [segment, recovery].compactMap({ $0 }) {
          let seconds = max(0, part.seconds)
          steps.append(Step(id: steps.count, segment: part, repetition: repetition,
            startSeconds: elapsed, endSeconds: elapsed + seconds))
          elapsed += seconds
        }
      }
      index += recovery == nil ? 1 : 2
    }
  }

  static func pairedRecovery(after index: Int, in segments: [RunSegment]) -> RunSegment? {
    guard segments.indices.contains(index), segments.indices.contains(index + 1) else { return nil }
    let work = segments[index]
    let recovery = segments[index + 1]
    guard work.phase == .work, (work.repetitions ?? 1) > 1,
          recovery.phase == .recovery, recovery.repetitions == work.repetitions else { return nil }
    return recovery
  }

  struct Step: Identifiable {
    var id: Int
    var segment: RunSegment
    var repetition: Int
    var startSeconds: Int
    var endSeconds: Int
    var seconds: Int { endSeconds - startSeconds }
  }
}
