import Foundation

struct BackendMutation: Codable, Equatable, Identifiable {
  enum Entity: String, Codable { case baseline = "baseline_snapshot", context = "planning_context_snapshot", athlete, athleteDetails = "athlete_details", preferences = "training_preferences", availability = "availability_rule", equipment = "athlete_equipment", goal = "athlete_goal", block = "training_block", plan = "plan_version", result = "workout_result" }
  enum Operation: String, Codable { case create, update, delete, activatePlan = "activate_plan" }
  let id: UUID
  let entityType: Entity
  let entityId: UUID
  let operation: Operation
  let baseRevision: BackendRevision?
  let payload: BackendJSONValue
  init<T: Encodable>(_ entity: Entity, id: UUID, operation: Operation, revision: BackendRevision?, payload: T) throws {
    self.id = UUID(); entityType = entity; entityId = id; self.operation = operation; baseRevision = revision
    self.payload = try JSONDecoder().decode(BackendJSONValue.self, from: OnboardingAPIClient.encode(payload))
  }
  private enum CodingKeys: String, CodingKey { case id, entityType, entityId, operation, baseRevision, payload }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id.uuidString.lowercased(), forKey: .id); try c.encode(entityType, forKey: .entityType); try c.encode(entityId.uuidString.lowercased(), forKey: .entityId)
    try c.encode(operation, forKey: .operation); try c.encode(baseRevision, forKey: .baseRevision); try c.encode(payload, forKey: .payload)
  }
}
