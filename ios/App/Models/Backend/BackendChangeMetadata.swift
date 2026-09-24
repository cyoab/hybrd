import Foundation

extension BackendWire.SyncChange {
  struct Metadata { var type: String; var id: UUID; var revision: BackendRevision?; var sequence: BackendRevision; var deleted: Bool }
  var metadata: Metadata {
    switch self {
    case .athlete(let v): return Metadata(type: "athlete", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .athleteDetails(let v): return Metadata(type: "athlete_details", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .athleteGoal(let v): return Metadata(type: "athlete_goal", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .trainingPreferences(let v): return Metadata(type: "training_preferences", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .availabilityRule(let v): return Metadata(type: "availability_rule", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .availabilityOverride(let v): return Metadata(type: "availability_override", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .baselineSnapshot(let v): return Metadata(type: "baseline_snapshot", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .planningContextSnapshot(let v): return Metadata(type: "planning_context_snapshot", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .athleteEquipment(let v): return Metadata(type: "athlete_equipment", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .exercisePreference(let v): return Metadata(type: "exercise_preference", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .trainingBlock(let v): return Metadata(type: "training_block", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .planVersion(let v): return Metadata(type: "plan_version", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .workoutResult(let v): return Metadata(type: "workout_result", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .activitySourceRecord(let v): return Metadata(type: "activity_source_record", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .planChangeSet(let v): return Metadata(type: "plan_change_set", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .coachThread(let v): return Metadata(type: "coach_thread", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .coachMessage(let v): return Metadata(type: "coach_message", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .actionProposal(let v): return Metadata(type: "action_proposal", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .structuredDecision(let v): return Metadata(type: "structured_decision", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    case .entitlement(let v): return Metadata(type: "entitlement", id: v.entityId, revision: v.revision, sequence: v.sequence, deleted: v.operation == .delete)
    }
  }
}
