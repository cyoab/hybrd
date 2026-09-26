import Foundation
import SwiftData

@Model
final class StoredTrainingState {
  @Attribute(.unique) var key: String
  var payload: Data

  init(payload: Data) {
    key = "training-v1"
    self.payload = payload
  }
}
