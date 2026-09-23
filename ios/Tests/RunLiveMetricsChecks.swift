import Foundation

enum RunLiveMetricsChecks {
  static func run() throws {
    let start = Date(timeIntervalSince1970: 1_000_000)
    var workout = RunWorkoutTemplate.easyThirty.workout(on: start)
    workout.distanceMeters = 10_000
    var run = RunRecording(workout: workout,
      zones: PersonalHeartRateZones(zone2: 120, zone3: 140, zone4: 160, zone5: 180),
      source: .watch, startedAt: start, runningSince: start, checkpointAt: start)
    let now = start.addingTimeInterval(1_500)
    let empty = RunLiveMetrics(run: run, at: start, currentPace: nil)
    precondition(empty.pace == nil && !empty.paceIsLast && empty.averagePace == nil)
    precondition(empty.remainingMeters == 10_000 && empty.remainingSeconds == nil)
    run.updateDistance(5_000, at: 1_500)
    run.rememberPace(290, at: now)
    run.heartRate = 154; run.heartRateAt = now
    let live = RunLiveMetrics(run: run, at: now, currentPace: 290)
    precondition(live.pace == 290 && !live.paceIsLast && live.averagePace == 300)
    precondition(run.elapsed == 0, "Live average must use active time, not only completed pause intervals")
    precondition(live.remainingMeters == 5_000 && live.zone == .three && live.heartRate == 154)
    precondition(TrainingUnits(weight: .pounds, distance: .miles).paceNumber(live.averagePace) == "8:03")

    for invalid in [Double.nan, Double.infinity, 0, -20] {
      run.rememberPace(invalid, at: now.addingTimeInterval(1))
    }
    run.rememberPace(200, at: now.addingTimeInterval(-1))
    precondition(run.lastPace == RunPaceReading(secondsPerKilometer: 290, recordedAt: now))
    for invalidLive in [nil, Double.nan, Double.infinity, 0, -10] as [Double?] {
      let fallback = RunLiveMetrics(run: run, at: now, currentPace: invalidLive)
      precondition(fallback.pace == 290 && fallback.paceIsLast)
    }
    let stale = RunLiveMetrics(run: run, at: now.addingTimeInterval(21), currentPace: 290)
    precondition(stale.pace == 290 && stale.paceIsLast && stale.heartRate == nil && stale.zone == nil)
    run.pause(at: now)
    let paused = RunLiveMetrics(run: run, at: now.addingTimeInterval(100), currentPace: 290)
    precondition(paused.pace == 290 && paused.paceIsLast && paused.averagePace == 300)
    precondition(paused.remainingMeters == 5_000 && paused.zone == nil)
    let restored = try JSONDecoder().decode(RunRecording.self, from: JSONEncoder().encode(run))
    precondition(restored.lastPace == run.lastPace, "Last measured pace survives checkpoint recovery")
    run.resume(at: now.addingTimeInterval(100))
    precondition(RunLiveMetrics(run: run, at: now.addingTimeInterval(100), currentPace: nil).paceIsLast)
    run.rememberPace(280, at: now.addingTimeInterval(105))
    precondition(!RunLiveMetrics(run: run, at: now.addingTimeInterval(105), currentPace: 280).paceIsLast)
    run.updateDistance(10_100, at: 1_600)
    precondition(RunLiveMetrics(run: run, at: now, currentPace: nil).remainingMeters == 0)

    var timed = RunRecording(workout: RunWorkoutTemplate.easyThirty.workout(on: start),
      source: .watch, startedAt: start, runningSince: start, checkpointAt: start)
    let time = RunLiveMetrics(run: timed, at: start.addingTimeInterval(60), currentPace: nil)
    precondition(time.remainingMeters == nil && time.remainingSeconds == 1_740)
    timed.advanceStep(at: start.addingTimeInterval(60))
    let advanced = RunLiveMetrics(run: timed, at: start.addingTimeInterval(60), currentPace: nil)
    precondition(advanced.remainingSeconds == 1_500 && advanced.averagePace == nil && timed.meters == 0)
    precondition(RunLiveMetrics(run: timed, at: start.addingTimeInterval(3_000), currentPace: nil).remainingSeconds == 0)
    timed.workout.minutes = 0; timed.workout.segments = []
    precondition(RunLiveMetrics(run: timed, at: start, currentPace: nil).remainingSeconds == nil)

    for (bpm, zone) in [(119.0, HeartRateZone.one), (120, .two), (140, .three), (160, .four), (180, .five)] {
      var sample = restored
      sample.resume(at: now); sample.heartRate = bpm; sample.heartRateAt = now
      precondition(RunLiveMetrics(run: sample, at: now, currentPace: nil).zone == zone)
      sample.zones = nil
      precondition(RunLiveMetrics(run: sample, at: now, currentPace: nil).zone == nil, "Never substitute the target for the actual zone")
    }
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as! [String: Any]
    legacy.removeValue(forKey: "lastPace")
    let old = try JSONDecoder().decode(RunRecording.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(old.lastPace == nil && old.meters == restored.meters)
    print("PASS: retained/invalid/stale pace, checkpoint and legacy recovery, live and paused average pace, distance/time remaining, zero-floor goals, metric/imperial pace and all current HR zones")
  }
}
