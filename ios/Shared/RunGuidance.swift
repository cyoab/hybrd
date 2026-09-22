import Foundation

/// A snapshot of the prescribed sequence at the recording's active time.
/// Skipping an interval advances guidance only, never recorded time or distance.
struct RunGuidance {
  var steps: [RunTimeline.Step]
  var current: RunTimeline.Step?
  var next: RunTimeline.Step?
  var remaining: Double
  var fraction: Double

  init(run: RunRecording, at date: Date) {
    let steps = RunTimeline(segments: run.workout.segments).steps
    self.steps = steps
    let time = run.seconds(at: date) + run.intervalOffset
    let index = steps.firstIndex { Double($0.endSeconds) > time }
    current = index.map { steps[$0] }
    next = index.flatMap { steps.dropFirst($0 + 1).first { $0.seconds > 0 } }
    remaining = current.map { max(0, Double($0.endSeconds) - time) } ?? 0
    fraction = current.map { min(1, max(0, (time - Double($0.startSeconds)) / Double(max(1, $0.seconds)))) } ?? 1
  }
}
