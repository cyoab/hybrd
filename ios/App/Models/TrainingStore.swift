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
  private(set) var progressRevision = 0
  @ObservationIgnored private var progressCache: [ProgressPeriod: ProgressSnapshot] = [:]
  @ObservationIgnored private var progressCacheNextResult: Date?
  @ObservationIgnored private var progressCacheDay: Date?
  @ObservationIgnored private var progressCacheZone: String?
  var companion = CompanionBridge()
  @ObservationIgnored private var backendExerciseNames: Set<String>?
  @ObservationIgnored private var backendPersist: ((TrainingState, TrainingState) throws -> Void)?
  var isBackendConnected: Bool { backendPersist != nil }
  func connectBackend(exerciseNames: Set<String>, _ persist: @escaping (TrainingState, TrainingState) throws -> Void) { backendExerciseNames = exerciseNames; backendPersist = persist }
  func restoreBackend(_ restored: TrainingState) {
    state = restored; isLoaded = true; progressRevision += 1; progressCache.removeAll(); shareWithWatch()
  }
  func disconnectBackend() { backendPersist = nil; backendExerciseNames = nil; load() }

  private var container: ModelContainer?
  private var record: StoredTrainingState?

  init() {
    load()
    companion.onRunReceived = { [weak self] run in self?.saveRecordedRun(run) ?? false }
    companion.retryTransfers()
  }

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
      let protectedIDs = Set(state.results.map(\.logicalWorkoutID) + state.drafts.map(\.id))
      if let upgraded = HeartRatePlanUpgrade.apply(to: plan, retaining: protectedIDs) {
        var upgradedState = state
        upgradedState.plans.append(upgraded)
        record?.payload = try JSONEncoder().encode(upgradedState)
        try container.mainContext.save()
        state = upgradedState
      }
      progressRevision += 1
      progressCache.removeAll()
      isLoaded = true
      loadError = nil
      shareWithWatch()
    } catch {
      loadError = L10n.text("Your training data could not be opened. It has not been reset. \(error.localizedDescription)")
    }
  }

  @discardableResult
  private func persist(_ next: TrainingState, share: Bool = true) -> Bool {
    if let backendPersist {
      do {
        try backendPersist(state, next); state = next; progressRevision += 1; progressCache.removeAll()
        if share { shareWithWatch() }; return true
      } catch { errorMessage = BackendErrorMessage.text(error); return false }
    }
    guard let container, let record else { return false }
    do {
      record.payload = try JSONEncoder().encode(next)
      try container.mainContext.save()
      if state.results != next.results || state.plans.last?.id != next.plans.last?.id {
        progressRevision += 1
        progressCache.removeAll()
      }
      state = next
      if share { shareWithWatch() }
      return true
    } catch {
      container.mainContext.rollback()
      errorMessage = L10n.text("Your changes could not be saved. Please try again. \(error.localizedDescription)")
      return false
    }
  }

  func progress(for period: ProgressPeriod, now: Date = Date()) -> ProgressSnapshot {
    _ = progressRevision
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: now)
    if progressCacheDay != day || progressCacheZone != calendar.timeZone.identifier ||
      (progressCacheNextResult.map { now >= $0 } ?? false) {
      progressCache.removeAll()
      progressCacheDay = day
      progressCacheZone = calendar.timeZone.identifier
    }
    if let cached = progressCache[period], now >= cached.asOf { return cached }
    progressCacheNextResult = state.results.lazy.map(\.completedAt).filter { $0 > now }.min()
    let snapshot = ProgressSnapshot(results: state.results, plans: state.plans, period: period, now: now, calendar: calendar)
    progressCache[period] = snapshot
    return snapshot
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
    if let result = result(for: workout) { return result.status.displayName }
    if hasDraft(for: workout) { return L10n.text("In progress") }
    if workout.date < Calendar.current.startOfDay(for: Date()) { return L10n.text("Not logged") }
    return workout.isKey ? L10n.text("Key session") : L10n.text("Planned")
  }

  @discardableResult
  func saveProfile(_ profile: TrainingProfile, replacing expected: TrainingProfile) -> Bool {
    guard state.profile == expected else {
      errorMessage = L10n.text("Your profile changed while you were editing. Reopen it to use the latest details.")
      return false
    }
    guard profile.validationMessage == nil else {
      errorMessage = profile.validationMessage
      return false
    }
    var next = state
    next.profile = profile
    next.profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if next.profile.name.isEmpty { next.profile.name = "Athlete" }
    return persist(next)
  }

  func starterProposal(for profile: TrainingProfile) -> TrainingPlan? {
    guard profile.validationMessage == nil, profile.supportsStarterPlan else { return nil }
    var updated = profile
    updated.isSample = false
    updated.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if updated.name.isEmpty { updated.name = "Athlete" }
    var proposal = TrainingEngine.makePlan(profile: updated, basePlanID: plan.id, availableExerciseNames: backendExerciseNames)
    if backendExerciseNames != nil, proposal.workouts.contains(where: { $0.kind == .strength && $0.exercises.isEmpty }) {
      errorMessage = L10n.text("The server catalog does not yet have enough exercises for this gym setup.")
      return nil
    }
    // Review and accept the same snapshot, including retained historical prescriptions.
    let retained = workouts.filter {
      result(for: $0) != nil || hasDraft(for: $0) || $0.date < Calendar.current.startOfDay(for: Date())
    }
    let occupied = Set(retained.map { Calendar.current.startOfDay(for: $0.date) })
    proposal.workouts = retained + proposal.workouts.filter { !occupied.contains($0.date) }
    return proposal
  }

  @discardableResult
  func accept(proposal: TrainingPlan) -> Bool {
    guard proposal.basePlanID == plan.id else {
      errorMessage = L10n.text("Your plan changed while you were reviewing. Return to your profile and review the latest block.")
      return false
    }
    guard proposal.profile.validationMessage == nil else {
      errorMessage = proposal.profile.validationMessage
      return false
    }
    var next = state
    next.profile = proposal.profile
    next.plans.append(proposal)
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
    guard draft.canFinish else { return false }
    var result = WorkoutResult(
      plannedWorkoutID: draft.workout.id, logicalWorkoutID: draft.workout.logicalID,
      kind: draft.workout.kind,
      status: !run && !draft.hasAllPrescribedSets ? .partial : .completed,
      durationSeconds: run ? draft.durationMinutes * 60 : max(1, Int(draft.activeSeconds())),
      distanceMeters: run ? Int((draft.distanceKilometers * 1_000).rounded()) : nil,
      effort: draft.effort, notes: draft.notes, sets: completed)
    if !run {
      result.performedStartedAt = draft.performedStartedAt
      result.performedEndedAt = draft.performedStartedAt == nil ? nil : result.completedAt
      result.performedTimeZoneID = draft.performedTimeZoneID
    }
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
      errorMessage = L10n.text("The plan changed while you were reviewing. Open the session again to review the current plan.")
      return false
    }
    guard result(for: workout) == nil, !hasDraft(for: workout) else { return false }
    var next = state
    next.plans.append(TrainingEngine.moving(workout, to: date, in: plan))
    return persist(next)
  }

  @discardableResult
  func addRun(_ template: RunWorkoutTemplate, on date: Date, expectedPlanID: UUID) -> Bool {
    guard isLoaded, plan.id == expectedPlanID else {
      errorMessage = L10n.text("Your plan changed while you were reviewing. Reopen this workout to review the latest schedule.")
      return false
    }
    guard date.timeIntervalSinceReferenceDate.isFinite,
          Calendar.current.startOfDay(for: date) >= Calendar.current.startOfDay(for: Date()) else {
      errorMessage = L10n.text("Choose today or a future date for this session.")
      return false
    }
    var next = state
    next.plans.append(TrainingEngine.adding(template.workout(on: date), to: plan))
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

  @discardableResult
  func saveRecordedRun(_ run: RunRecording, asSeparate: Bool = false) -> Bool {
    if isBackendConnected && !asSeparate && !state.plans.flatMap(\.workouts).contains(where: { $0.id == run.workout.id }) { return false }
    guard run.isFinished, run.canSave else { errorMessage = L10n.text("This recording needs a positive distance and time before saving."); return false }
    if state.results.contains(where: { $0.id == run.id }) { return true }
    if !asSeparate && state.results.contains(where: { $0.logicalWorkoutID == run.workout.logicalID }) { return false }
    var result = run.result()
    if asSeparate { result.logicalWorkoutID = result.id }
    var next = state
    next.results.append(result)
    next.drafts.removeAll { $0.id == result.logicalWorkoutID }
    return persist(next)
  }

  func previousSets(for exerciseName: String) -> [LoggedSet] {
    let previous = state.results.filter { $0.kind == .strength && $0.status != .skipped }
      .sorted { $0.completedAt > $1.completedAt }
      .first { result in result.sets.contains { $0.exerciseName == exerciseName } }
    return previous?.sets.filter { $0.exerciseName == exerciseName } ?? []
  }

  func shareWithWatch() {
    let pending = workouts.filter { result(for: $0) == nil && $0.date >= Calendar.current.startOfDay(for: Date()) }
    companion.publish(CompanionSnapshot(name: profile.name, isSample: profile.isSample, workouts: Array(pending.prefix(12)), heartRateZones: profile.athlete?.heartRateZones, units: profile.trainingUnits))
  }
}
