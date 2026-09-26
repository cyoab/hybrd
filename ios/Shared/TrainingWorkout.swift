import Foundation

struct TrainingWorkout: Codable, Identifiable, Equatable {
  var id = UUID()
  var logicalID = UUID()
  var date: Date
  var timeZoneID = TimeZone.current.identifier
  var kind: WorkoutKind
  var title: String
  var purpose: String
  var minutes: Int
  var distanceMeters: Int = 0
  var effort = "Easy running"
  var isKey = false
  var exercises: [ExercisePrescription] = []
  var segments: [RunSegment] = []
  var scheduledMinutes: Int?
  var isOptional: Bool?
  var runType: RunWorkoutType?
  var planVersionID: UUID?
  var executableVersion: Int?
  var estimatedDurationSeconds: Int?
  var instructions: String?
  var prescriptionNotes: String?
  var primaryTargetType: String?
  var sessionFocus: String?
  var requiresCanonicalSync: Bool?

  var executionIssue: String? {
    if requiresCanonicalSync == true { return L10n.text("Sync this updated workout before starting.") }
    if let executableVersion, executableVersion > 2 { return L10n.text("Update hybrd to perform this prescription.") }
    if kind == .run && (segments.count > 2_000 || segments.contains { $0.targets != nil && $0.targets?.completion == nil }) {
      return L10n.text("This run uses completion rules that this version of hybrd cannot execute. Review it with your coach before starting.")
    }
    return nil
  }

  var localizedTitle: String { L10n.content(title) }
  var localizedPurpose: String { L10n.content(purpose) }
  var resolvedRunType: RunWorkoutType {
    runType ?? RunWorkoutType.legacyType(for: title)
  }

  private var workZones: [HeartRateZone] {
    Array(Set(segments.filter { $0.phase == .work }.compactMap(\.heartRateZone))).sorted()
  }

  var primaryHeartRateZone: HeartRateZone? {
    if let zone = workZones.last { return zone }
    if let easy = segments.first(where: { $0.phase == .easy }) { return easy.heartRateZone }
    return segments.compactMap(\.heartRateZone).max()
  }

  var heartRateTargetCaption: String {
    workZones.count > 1 ? L10n.text("highest work target") : segments.contains { $0.phase == .work } ? L10n.text("work target") : L10n.text("main HR target")
  }

  var prescriptionTarget: String {
    guard kind == .run else { return L10n.content(effort) }
    if let first = workZones.first, let last = workZones.last, first != last {
      return L10n.text("\(first.shortTitle)–\(last.shortTitle) work")
    }
    guard let zone = primaryHeartRateZone else { return L10n.text("HR target not set") }
    return segments.contains { $0.phase == .work } ? L10n.text("\(zone.title) work") : L10n.text("\(zone.title) focus")
  }

  var scheduledTimeLabel: String? {
    guard let scheduledMinutes else { return nil }
    return String(format: "%02d:%02d", scheduledMinutes / 60, scheduledMinutes % 60)
  }

  var summary: String {
    if kind == .run && distanceMeters == 0 { return L10n.text("\(minutes) min · Time-based run") }
    return kind == .run ? L10n.text("\(Double(distanceMeters) / 1_000, specifier: "%.1f") km · \(minutes) min") : L10n.text("\(exercises.count) exercises · \(minutes) min")
  }

  func reidentified() -> TrainingWorkout {
    var copy = self
    copy.id = UUID()
    if executableVersion == 2 { copy.requiresCanonicalSync = true; copy.planVersionID = nil }
    copy.exercises = exercises.map { exercise in
      var item = exercise
      item.id = UUID()
      item.sets = exercise.sets.map { set in
        var newSet = set
        newSet.id = UUID()
        return newSet
      }
      return item
    }
    copy.segments = segments.map { segment in
      var item = segment
      item.id = UUID()
      return item
    }
    return copy
  }
}

enum WorkoutKind: String, Codable, CaseIterable, Identifiable {
  var displayName: String { L10n.content(rawValue) }
  case run = "Run"
  case strength = "Strength"
  var id: String { rawValue }
  var symbol: String { self == .run ? "figure.run" : "dumbbell.fill" }
}

struct ExercisePrescription: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var note: String
  var localizedName: String { L10n.content(name) }
  var localizedNote: String { L10n.content(note) }
  var restSeconds = 90
  var sets: [SetPrescription]
  var canonicalExerciseID: UUID?
  var supersetGroupID: UUID?
  var substitutionAllowed: Bool?
  var substitutions: [ExerciseSubstitution]?
}

struct SetPrescription: Codable, Identifiable, Equatable {
  var id = UUID()
  var reps: Int
  var targetRIR = 3
  var targets: StrengthSetTargets?
}

struct RunSegment: Codable, Identifiable, Equatable {
  var id = UUID()
  var title: String
  var seconds: Int
  var cue: String
  var phase: RunSegmentPhase?
  var repetitions: Int?
  var target: String?
  var heartRateZone: HeartRateZone?
  var targets: RunStepTargets?
  var reference: RunStepReference?

  var localizedTitle: String { L10n.content(title) }
  var localizedCue: String { L10n.content(cue) }
  var displayTitle: String {
    if let repetitions, repetitions > 1 { return localizedTitle + " × " + String(repetitions) }
    return localizedTitle
  }

  var targetSummary: String {
    durationTargetSummary + (heartRateZone.map { " · " + $0.shortTitle } ?? "")
  }

  var durationTargetSummary: String {
    if let targets { return targets.summary(units: .metric) }
    let duration = seconds.isMultiple(of: 60) ? L10n.text("\(seconds / 60) min") : L10n.text("\(seconds / 60):\(String(format: "%02d", seconds % 60)) min")
    return duration + (target.map { " " + L10n.content($0) } ?? "")
  }

  var totalSeconds: Int { seconds * max(1, repetitions ?? 1) }
}

enum RunSegmentPhase: String, Codable {
  case warmUp, work, recovery, coolDown, easy, stride
}

extension String.StringInterpolation {
  mutating func appendInterpolation(_ value: Double, specifier: String) {
    appendLiteral(String(format: specifier, value))
  }
}
