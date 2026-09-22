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

  var primaryHeartRateZone: HeartRateZone? {
    if let work = segments.first(where: { $0.phase == .work }) { return work.heartRateZone }
    if let easy = segments.first(where: { $0.phase == .easy }) { return easy.heartRateZone }
    return segments.compactMap(\.heartRateZone).max()
  }

  var heartRateTargetCaption: String {
    segments.contains { $0.phase == .work } ? "work target" : "main HR target"
  }

  var prescriptionTarget: String {
    guard kind == .run else { return effort }
    guard let zone = primaryHeartRateZone else { return "HR target not set" }
    return zone.title + (segments.contains { $0.phase == .work } ? " work" : " focus")
  }

  var scheduledTimeLabel: String? {
    guard let scheduledMinutes else { return nil }
    return String(format: "%02d:%02d", scheduledMinutes / 60, scheduledMinutes % 60)
  }

  var summary: String {
    kind == .run ? "\(Double(distanceMeters) / 1_000, specifier: "%.1f") km · \(minutes) min" : "\(exercises.count) exercises · \(minutes) min"
  }

  func reidentified() -> TrainingWorkout {
    var copy = self
    copy.id = UUID()
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
  case run = "Run"
  case strength = "Strength"
  var id: String { rawValue }
  var symbol: String { self == .run ? "figure.run" : "dumbbell.fill" }
}

struct ExercisePrescription: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var note: String
  var restSeconds = 90
  var sets: [SetPrescription]
}

struct SetPrescription: Codable, Identifiable, Equatable {
  var id = UUID()
  var reps: Int
  var targetRIR = 3
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

  var displayTitle: String {
    if let repetitions, repetitions > 1 { return title + " × " + String(repetitions) }
    return title
  }

  var targetSummary: String {
    durationTargetSummary + (heartRateZone.map { " · " + $0.shortTitle } ?? "")
  }

  var durationTargetSummary: String {
    let duration = seconds.isMultiple(of: 60) ? "\(seconds / 60) min" : "\(seconds / 60):\(String(format: "%02d", seconds % 60)) min"
    return duration + (target.map { " " + $0 } ?? "")
  }

  var totalSeconds: Int { seconds * max(1, repetitions ?? 1) }
}

enum RunSegmentPhase: String, Codable {
  case warmUp, work, recovery, coolDown, easy
}

extension String.StringInterpolation {
  mutating func appendInterpolation(_ value: Double, specifier: String) {
    appendLiteral(String(format: specifier, value))
  }
}
