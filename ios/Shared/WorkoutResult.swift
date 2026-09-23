import Foundation

struct WorkoutResult: Codable, Identifiable, Equatable {
  var id = UUID()
  var plannedWorkoutID: UUID
  var logicalWorkoutID: UUID
  var completedAt = Date()
  var kind: WorkoutKind
  var status: ResultStatus
  var durationSeconds: Int
  var distanceMeters: Int?
  var effort: Int
  var notes: String
  var sets: [LoggedSet]
  var run: RunRecording?
}

enum ResultStatus: String, Codable {
  var displayName: String { L10n.content(rawValue) }
  case completed = "Completed"
  case partial = "Partial"
  case skipped = "Skipped"
}

struct LoggedSet: Codable, Identifiable, Equatable {
  var id = UUID()
  var prescriptionID: UUID?
  var localizedExerciseName: String { L10n.content(exerciseName) }
  var exerciseName: String
  var reps: Int
  var kilograms: Double
  var isComplete = false
  var rir: Int?
}

struct WorkoutDraft: Codable, Identifiable, Equatable {
  var id: UUID { workout.logicalID }
  var workout: TrainingWorkout
  var startedAt = Date()
  var distanceKilometers: Double = 0
  var durationMinutes = 0
  var effort = 5
  var notes = ""
  var sets: [LoggedSet] = []
  var elapsedSeconds: TimeInterval?
  var runningSince: Date?
  var rest: StrengthRestTimer?

  var validationMessage: String? { validationMessage(in: .metric) }
  func validationMessage(in units: TrainingUnits) -> String? {
    if workout.kind == .run {
      guard distanceKilometers.isFinite, distanceKilometers >= 0.001, distanceKilometers <= 500,
        durationMinutes > 0, durationMinutes <= 2_880 else {
        return L10n.text("Enter a distance up to \(units.distanceText(500_000)) and a duration up to 2,880 minutes. Both must be greater than zero.")
      }
    } else {
      let completed = sets.filter(\.isComplete)
      guard !completed.isEmpty else { return L10n.text("Check at least one completed set.") }
      guard completed.allSatisfy({ $0.reps > 0 && $0.reps <= 100 && $0.kilograms.isFinite && (0...1_000).contains($0.kilograms) && ($0.rir.map { (0...10).contains($0) } ?? true) }) else {
        return L10n.text("Completed sets need 1–100 reps and a load between 0 and \(units.weightText(1_000)), with RIR from 0 to 10 when entered.")
      }
    }
    return nil
  }

  var canFinish: Bool { validationMessage == nil }

  var hasAllPrescribedSets: Bool {
    let prescribed = Set(workout.exercises.flatMap(\.sets).map(\.id))
    let performed = Set(sets.filter(\.isComplete).compactMap(\.prescriptionID))
    return performed.isSuperset(of: prescribed)
  }

  func activeSeconds(at now: Date = Date()) -> TimeInterval {
    max(0, elapsedSeconds ?? 0) + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
  }

  mutating func resume(at now: Date = Date()) {
    if runningSince == nil { runningSince = now }
  }

  mutating func pause(at now: Date = Date()) {
    elapsedSeconds = activeSeconds(at: now)
    runningSince = nil
  }

  mutating func addSet(for exercise: ExercisePrescription) {
    let previous = sets.last { $0.exerciseName == exercise.name }
    sets.append(LoggedSet(prescriptionID: nil, exerciseName: exercise.name,
      reps: previous?.reps ?? exercise.sets.first?.reps ?? 6,
      kilograms: previous?.kilograms ?? 0))
  }

  init(workout: TrainingWorkout) {
    self.workout = workout
    elapsedSeconds = 0
    // Actual run values start empty; prescriptions are never recorded as performed work.
    sets = workout.exercises.flatMap { exercise in
      exercise.sets.map { set in
        LoggedSet(prescriptionID: set.id, exerciseName: exercise.name, reps: set.reps, kilograms: 0)
      }
    }
  }
}
