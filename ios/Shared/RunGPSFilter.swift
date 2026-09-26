import Foundation

/// Rejects stale, imprecise and implausible fixes; never bridges a pause or a GPS outage.
struct RunGPSFilter {
  private(set) var previous: RunLocation?
  mutating func reset() { previous = nil }
  mutating func accept(_ input: RunLocation, now: Date, after start: Date) -> Accepted? {
    guard input.latitude.isFinite, input.longitude.isFinite, input.accuracy.isFinite, input.altitude.isFinite,
      (-90...90).contains(input.latitude), (-180...180).contains(input.longitude),
      (0...25).contains(input.accuracy), abs(input.timestamp.timeIntervalSince(now)) <= 12,
      input.timestamp >= start else { return nil }
    var point = input
    var distance = 0.0
    var seconds = 0.0
    point.startsSegment = previous == nil
    if let previous {
      seconds = point.timestamp.timeIntervalSince(previous.timestamp)
      guard seconds > 0 else { return nil }
      if seconds > 15 { point.startsSegment = true }
      else {
        let measured = Self.distance(previous, point)
        guard measured / seconds <= 12, measured >= 3 else { return nil }
        distance = measured
      }
    }
    previous = point
    return Accepted(point: point, meters: distance, seconds: seconds)
  }
  static func distance(_ first: RunLocation, _ second: RunLocation) -> Double {
    let radians = Double.pi / 180
    let latitude = (second.latitude - first.latitude) * radians
    let longitude = (second.longitude - first.longitude) * radians
    let a = pow(sin(latitude / 2), 2) + cos(first.latitude * radians) * cos(second.latitude * radians) * pow(sin(longitude / 2), 2)
    return 6_371_000 * 2 * atan2(sqrt(max(0, a)), sqrt(max(0, 1 - a)))
  }
  struct Accepted { var point: RunLocation; var meters: Double; var seconds: Double }
}
