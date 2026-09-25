import Foundation

/// A snapshot of the prescribed sequence at the recording's active time.
/// Skipping an interval advances guidance only, never recorded time or distance.
struct RunGuidance {
  var steps: [RunTimeline.Step]
  var current: RunTimeline.Step?
  var next: RunTimeline.Step?
  var remaining: Double
  var fraction: Double
  var remainingMeters: Double?

  func remainingLabel(units: TrainingUnits) -> String {
    remainingMeters.map { units.distanceText($0, decimals: 2) } ?? RunRecording.clock(remaining)
  }

  init(run: RunRecording, at date: Date) {
    let steps = RunTimeline(segments: run.workout.segments).steps
    self.steps = steps
    let time = run.seconds(at: date) + run.intervalOffset
    let index = run.workout.executableVersion == 2
      ? steps.indices.first { $0 == (run.execution?.index ?? 0) }
      : steps.firstIndex { Double($0.endSeconds) > time }
    current = index.map { steps[$0] }
    next = index.flatMap { steps.dropFirst($0 + 1).first { $0.seconds > 0 || $0.segment.targets?.distanceM != nil } }
    remaining = current.map { max(0, Double($0.endSeconds) - time) } ?? 0
    if run.workout.executableVersion == 2, let current {
      switch current.segment.targets?.completion ?? .duration(current.seconds) {
      case .distance(let target):
        let done = max(0, run.meters - (run.execution?.startMeters ?? 0))
        remainingMeters = max(0, target - done); remaining = 0; fraction = min(1, done / max(1, target)); return
      case .duration(let target):
        let done = max(0, run.seconds(at: date) - (run.execution?.startActiveSeconds ?? 0))
        remaining = max(0, Double(target) - done); fraction = min(1, done / Double(max(1, target))); return
      }
    }
    fraction = current.map { min(1, max(0, (time - Double($0.startSeconds)) / Double(max(1, $0.seconds)))) } ?? 1
  }
}
