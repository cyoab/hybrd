import Foundation
import Observation

@Observable
final class AthleteProfileEditor {
  var profile: TrainingProfile
  var details: AthleteDetails
  var weeklyDistance = ""
  var weight = ""
  var height = ""
  var zoneStarts = ["", "", "", ""]
  var runningTimes: [RunRecordDistance: String] = [:]
  private var weeklyBaseline: Double
  private var weightBaseline: Double?
  private var initialWeeklyText: String
  private var initialWeightText: String
  var units: TrainingUnits { profile.trainingUnits }
  let original: TrainingProfile

  init(profile: TrainingProfile) {
    original = profile
    self.profile = profile
    details = profile.athlete ?? AthleteDetails()
    weeklyBaseline = profile.weeklyKilometers
    weightBaseline = profile.athlete?.weightKilograms
    initialWeeklyText = profile.trainingUnits.distanceInput(profile.weeklyKilometers * 1_000)
    initialWeightText = profile.athlete?.weightKilograms.map { profile.trainingUnits.weightInput($0) } ?? ""
    weeklyDistance = initialWeeklyText
    weight = initialWeightText
    height = details.heightCentimeters.map { $0.formatted(.number.grouping(.never)) } ?? ""
    zoneStarts = details.heartRateZones?.starts.map(String.init) ?? ["", "", "", ""]
    runningTimes = Dictionary(details.runningBests.map { ($0.distance, $0.time) }, uniquingKeysWith: { first, _ in first })
  }
  var parsedWeeklyKilometers: Double? {
    if weeklyDistance == initialWeeklyText { return weeklyBaseline.isFinite && profile.baselineRange.contains(weeklyBaseline) ? weeklyBaseline : nil }
    return units.distance.parse(weeklyDistance, meters: (profile.baselineRange.lowerBound * 1000)...(profile.baselineRange.upperBound * 1000)).map { $0 / 1_000 }
  }
  var parsedWeightKilograms: Double? {
    if weight == initialWeightText { return weightBaseline.flatMap { $0.isFinite && (20...400).contains($0) ? $0 : nil } }
    return units.weight.parse(weight, kilograms: 20...400)
  }
  var canChangeWeightUnit: Bool { weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedWeightKilograms != nil }
  var weeklyDistanceError: String { L10n.text("Weekly distance: enter \(units.distanceText(profile.baselineRange.lowerBound * 1000))–\(units.distanceText(profile.baselineRange.upperBound * 1000)).") }
  var weightError: String { L10n.text("Weight: enter \(units.weightText(20))–\(units.weightText(400)) or leave it blank.") }

  func setWeightUnit(_ unit: TrainingWeightUnit) {
    guard canChangeWeightUnit, unit != units.weight else { return }
    weightBaseline = parsedWeightKilograms
    var value = units; value.weight = unit; profile.units = value
    initialWeightText = weightBaseline.map { value.weightInput($0) } ?? ""
    weight = initialWeightText
  }
  func setDistanceUnit(_ unit: TrainingDistanceUnit) {
    guard let kilometers = parsedWeeklyKilometers, unit != units.distance else { return }
    weeklyBaseline = kilometers
    var value = units; value.distance = unit; profile.units = value
    initialWeeklyText = value.distanceInput(kilometers * 1_000)
    weeklyDistance = initialWeeklyText
  }
  func importWeight(kilograms: Double) {
    weightBaseline = kilograms
    initialWeightText = units.weightInput(kilograms)
    weight = initialWeightText
  }
  var validationMessage: String? {
    if parsedWeeklyKilometers == nil { return weeklyDistanceError }
    if !weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
       parsedWeightKilograms == nil { return weightError }
    if !height.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
       TrainingProfile.parseDecimal(height, range: 80...250) == nil { return L10n.text("Height: enter 80–250 cm or leave it blank.") }
    if zoneStarts.contains(where: { !$0.isEmpty }) && zones == nil { return L10n.text("HR zones: enter four increasing boundaries from 30–250 bpm, or clear all.") }
    if runningTimes.values.contains(where: { !$0.isEmpty && RunningPersonalBest.parse($0) == nil }) {
      return L10n.text("Running PRs: use mm:ss or h:mm:ss, such as 24:30.")
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
    if original.units == nil && units == .metric { result.units = nil }
    var info = details
    result.weeklyKilometers = parsedWeeklyKilometers ?? profile.weeklyKilometers
    info.weightKilograms = parsedWeightKilograms
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
