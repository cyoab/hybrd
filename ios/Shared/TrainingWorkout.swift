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
  var effort = "Easy · RPE 3–4"
  var isKey = false
  var exercises: [ExercisePrescription] = []
  var segments: [RunSegment] = []

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
}

extension String.StringInterpolation {
  mutating func appendInterpolation(_ value: Double, specifier: String) {
    appendLiteral(String(format: specifier, value))
  }
}
