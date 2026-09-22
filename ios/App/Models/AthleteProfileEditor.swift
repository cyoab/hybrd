import Foundation
import Observation

@Observable
final class AthleteProfileEditor {
  var profile: TrainingProfile
  var details: AthleteDetails
  var weeklyDistance: String
  var weight = ""
  var height = ""
  var zoneStarts = ["", "", "", ""]
  var runningTimes: [RunRecordDistance: String] = [:]
  let original: TrainingProfile

  init(profile: TrainingProfile) {
    original = profile
    self.profile = profile
    details = profile.athlete ?? AthleteDetails()
    weeklyDistance = profile.weeklyKilometers.formatted(.number.grouping(.never))
    weight = details.weightKilograms.map { $0.formatted(.number.grouping(.never)) } ?? ""
    height = details.heightCentimeters.map { $0.formatted(.number.grouping(.never)) } ?? ""
    zoneStarts = details.heartRateZones?.starts.map(String.init) ?? ["", "", "", ""]
    runningTimes = Dictionary(details.runningBests.map { ($0.distance, $0.time) }, uniquingKeysWith: { first, _ in first })
  }
  var validationMessage: String? {
    if TrainingProfile.parseWeeklyKilometers(weeklyDistance) == nil { return "Weekly distance: enter 3–150 km." }
    if !weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
       TrainingProfile.parseDecimal(weight, range: 20...400) == nil { return "Weight: enter 20–400 kg or leave it blank." }
    if !height.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
       TrainingProfile.parseDecimal(height, range: 80...250) == nil { return "Height: enter 80–250 cm or leave it blank." }
    if zoneStarts.contains(where: { !$0.isEmpty }) && zones == nil { return "HR zones: enter four increasing boundaries from 30–250 bpm, or clear all." }
    if runningTimes.values.contains(where: { !$0.isEmpty && RunningPersonalBest.parse($0) == nil }) {
      return "Running PRs: use mm:ss or h:mm:ss, such as 24:30."
    }
    return assembledProfile.validationMessage
  }
  var zones: PersonalHeartRateZones? {
    let values = zoneStarts.compactMap { Int($0) }
    guard values.count == 4 else { return nil }
    let zones = PersonalHeartRateZones(zone2: values[0], zone3: values[1], zone4: values[2], zone5: values[3])
    return zones.isValid ? zones : nil
  }
  var assembledProfile: TrainingProfile {
    var result = profile
    var info = details
    result.weeklyKilometers = TrainingProfile.parseWeeklyKilometers(weeklyDistance) ?? profile.weeklyKilometers
    info.weightKilograms = TrainingProfile.parseDecimal(weight, range: 20...400)
    info.heightCentimeters = TrainingProfile.parseDecimal(height, range: 80...250)
    info.heartRateZones = zones
    info.runningBests = RunRecordDistance.allCases.compactMap { distance in
      RunningPersonalBest.parse(runningTimes[distance] ?? "").map { RunningPersonalBest(distance: distance, seconds: $0) }
    }
    result.athlete = info
    return result
  }
  var hasChanges: Bool {
    var baseline = original
    baseline.athlete = original.athlete ?? AthleteDetails()
    return validationMessage != nil || assembledProfile != baseline
  }
}
