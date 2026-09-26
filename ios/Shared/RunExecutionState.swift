import Foundation

/// Observed interval boundaries, separate from overlapping manual/automatic laps.
struct RunExecutionState: Codable, Equatable {
  var index = 0
  var startActiveSeconds: Double = 0
  var startMeters: Double = 0
  var events: [Event] = []

  struct Event: Codable, Equatable {
    enum End: String, Codable { case targetReached, manualAdvance, workoutFinished }
    var executionID: UUID
    var reference: RunStepReference?
    var startActiveSeconds: Double
    var endActiveSeconds: Double
    var startMeters: Double
    var endMeters: Double
    var reason: End
  }

  mutating func advance(steps: [RunTimeline.Step], activeSeconds: Double, meters: Double, reason: Event.End) {
    guard steps.indices.contains(index), activeSeconds >= startActiveSeconds, meters >= startMeters,
          activeSeconds.isFinite, meters.isFinite, events.count < 2_000 else { return }
    if reason == .workoutFinished && activeSeconds == startActiveSeconds && meters == startMeters { return }
    let step = steps[index]
    events.append(Event(executionID: step.segment.id, reference: step.segment.reference,
      startActiveSeconds: startActiveSeconds, endActiveSeconds: activeSeconds,
      startMeters: startMeters, endMeters: meters, reason: reason))
    index += 1; startActiveSeconds = activeSeconds; startMeters = meters
  }
  mutating func observe(steps: [RunTimeline.Step], activeSeconds: Double, meters: Double) {
    guard steps.indices.contains(index) else { return }
    let step = steps[index]
    let completion = step.segment.targets?.completion ?? (step.segment.targets == nil ? .duration(step.seconds) : nil)
    let reached: Bool
    switch completion {
    case .duration(let seconds): reached = seconds > 0 && activeSeconds - startActiveSeconds >= Double(seconds)
    case .distance(let distance): reached = meters - startMeters >= distance
    case nil: reached = false
    }
    // End at the observation that established completion; do not invent historical sample boundaries.
    if reached { advance(steps: steps, activeSeconds: activeSeconds, meters: meters, reason: .targetReached) }
  }
}
