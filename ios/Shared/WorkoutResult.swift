import Foundation

struct WorkoutResult: Codable, Identifiable {
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
}

enum ResultStatus: String, Codable {
  case completed = "Completed"
  case partial = "Partial"
  case skipped = "Skipped"
}

struct LoggedSet: Codable, Identifiable, Equatable {
  var id = UUID()
  var prescriptionID: UUID
  var exerciseName: String
  var reps: Int
  var kilograms: Double
  var isComplete = false
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

  init(workout: TrainingWorkout) {
    self.workout = workout
    // Actual run values start empty; prescriptions are never recorded as performed work.
    sets = workout.exercises.flatMap { exercise in
      exercise.sets.map { set in
        LoggedSet(prescriptionID: set.id, exerciseName: exercise.name, reps: set.reps, kilograms: 0)
      }
    }
  }
}
