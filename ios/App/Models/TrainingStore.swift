import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TrainingStore {
  private(set) var state = TrainingState.sample()
  private(set) var isLoaded = false
  var errorMessage: String?
  var loadError: String?
  var companion = CompanionBridge()
  private var container: ModelContainer?
  private var record: StoredTrainingState?

  init() { load() }

  var plan: TrainingPlan { state.plans.last! }
  var profile: TrainingProfile { state.profile }
  var workouts: [TrainingWorkout] { plan.workouts.sorted { $0.date < $1.date } }

  func load() {
    do {
      let container = try ModelContainer(for: StoredTrainingState.self)
      self.container = container
      let records = try container.mainContext.fetch(FetchDescriptor<StoredTrainingState>())
      if let saved = records.first {
        let decoded = try JSONDecoder().decode(TrainingState.self, from: saved.payload)
        guard decoded.schemaVersion == 1, !decoded.plans.isEmpty else {
          throw CocoaError(.coderReadCorrupt)
        }
        record = saved
        state = decoded
      } else {
        let saved = StoredTrainingState(payload: try JSONEncoder().encode(state))
        container.mainContext.insert(saved)
        try container.mainContext.save()
        record = saved
      }
      // Upgrade only an untouched sample, retaining the original snapshot.
      if state.profile.isSample, state.results.isEmpty, state.drafts.isEmpty,
         state.plans.count == 1, state.plans[0].workouts.allSatisfy({ $0.scheduledMinutes == nil }) {
        var sample = SampleTraining.makePlan(profile: state.profile)
        sample.basePlanID = state.plans[0].id
        state.plans.append(sample)
        record?.payload = try JSONEncoder().encode(state)
        try container.mainContext.save()
      }
      isLoaded = true
      loadError = nil
      shareWithWatch()
    } catch {
      loadError = "Your training data could not be opened. It has not been reset. \(error.localizedDescription)"
    }
  }

  @discardableResult
  private func persist(_ next: TrainingState, share: Bool = true) -> Bool {
    guard let container, let record else { return false }
    do {
      record.payload = try JSONEncoder().encode(next)
      try container.mainContext.save()
      state = next
      if share { shareWithWatch() }
      return true
    } catch {
      container.mainContext.rollback()
      errorMessage = "Your changes could not be saved. Please try again. \(error.localizedDescription)"
      return false
    }
  }

  func result(for workout: TrainingWorkout) -> WorkoutResult? {
    state.results.first { $0.logicalWorkoutID == workout.logicalID }
  }

  func draft(for workout: TrainingWorkout) -> WorkoutDraft {
    state.drafts.first { $0.id == workout.logicalID } ?? WorkoutDraft(workout: workout)
  }

  func hasDraft(for workout: TrainingWorkout) -> Bool {
    state.drafts.contains { $0.id == workout.logicalID }
  }

  func sessions(in week: Date) -> [TrainingWorkout] {
    let end = TrainingEngine.date(week, offset: 7)
    return workouts.filter { $0.date >= week && $0.date < end }
  }

  func status(of workout: TrainingWorkout) -> String {
    if let result = result(for: workout) { return result.status.rawValue }
    if hasDraft(for: workout) { return "In progress" }
    if workout.date < Calendar.current.startOfDay(for: Date()) { return "Not logged" }
    return workout.isKey ? "Key session" : "Planned"
  }

  @discardableResult
  func accept(profile: TrainingProfile) -> Bool {
    guard profile.availableDays.count >= 2 else { return false }
    var next = state
    var updated = profile
    updated.isSample = false
    updated.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if updated.name.isEmpty { updated.name = "Athlete" }
    let accepted = TrainingEngine.makePlan(profile: updated, basePlanID: plan.id)
    // Completed and in-progress sessions retain their exact historical prescriptions.
    let retained = workouts.filter { result(for: $0) != nil || hasDraft(for: $0) || $0.date < Calendar.current.startOfDay(for: Date()) }
    let occupied = Set(retained.map { Calendar.current.startOfDay(for: $0.date) })
    var merged = accepted
    merged.workouts = retained + accepted.workouts.filter { !occupied.contains($0.date) }
    next.profile = updated
    next.plans.append(merged)
    return persist(next)
  }

  func saveDraft(_ draft: WorkoutDraft) {
    var next = state
    next.drafts.removeAll { $0.id == draft.id }
    next.drafts.append(draft)
    persist(next, share: false)
  }

  @discardableResult
  func finish(_ draft: WorkoutDraft) -> Bool {
    guard result(for: draft.workout) == nil else { return false }
    let completed = draft.sets.filter(\.isComplete)
    let run = draft.workout.kind == .run
    guard run ? (draft.distanceKilometers > 0 && draft.durationMinutes > 0) : !completed.isEmpty else { return false }
    let result = WorkoutResult(
      plannedWorkoutID: draft.workout.id, logicalWorkoutID: draft.workout.logicalID,
      kind: draft.workout.kind,
      status: !run && completed.count < draft.sets.count ? .partial : .completed,
      durationSeconds: run ? draft.durationMinutes * 60 : max(60, Int(Date().timeIntervalSince(draft.startedAt))),
      distanceMeters: run ? Int(draft.distanceKilometers * 1_000) : nil,
      effort: draft.effort, notes: draft.notes, sets: completed)
    var next = state
    next.results.append(result)
    next.drafts.removeAll { $0.id == draft.id }
    return persist(next)
  }

  @discardableResult
  func skip(_ workout: TrainingWorkout) -> Bool {
    guard result(for: workout) == nil, !hasDraft(for: workout) else { return false }
    var next = state
    next.results.append(WorkoutResult(plannedWorkoutID: workout.id, logicalWorkoutID: workout.logicalID,
      kind: workout.kind, status: .skipped, durationSeconds: 0, effort: 0, notes: "", sets: []))
    return persist(next)
  }

  @discardableResult
  func move(_ workout: TrainingWorkout, to date: Date, expectedPlanID: UUID) -> Bool {
    guard plan.id == expectedPlanID else {
      errorMessage = "The plan changed while you were reviewing. Open the session again to review the current plan."
      return false
    }
    guard result(for: workout) == nil, !hasDraft(for: workout) else { return false }
    var next = state
    next.plans.append(TrainingEngine.moving(workout, to: date, in: plan))
    return persist(next)
  }

  func askCoach(_ question: String) {
    let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    var next = state
    next.messages.append(CoachMessage(text: text, isAthlete: true))
    next.messages.append(CoachMessage(text: LocalCoach.reply(to: text, state: state), isAthlete: false))
    persist(next, share: false)
  }

  func shareWithWatch() {
    let pending = workouts.filter { result(for: $0) == nil && $0.date >= Calendar.current.startOfDay(for: Date()) }
    companion.publish(CompanionSnapshot(name: profile.name, isSample: profile.isSample, workouts: Array(pending.prefix(12))))
  }
}
