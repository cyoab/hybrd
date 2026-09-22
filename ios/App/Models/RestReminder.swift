import Foundation
import UserNotifications

@MainActor enum RestReminder {
  private static var task: Task<Void, Never>?
  static func requestPermission() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let status = await center.notificationSettings().authorizationStatus
    if status == .authorized || status == .provisional { return true }
    guard status == .notDetermined else { return false }
    return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
  }
  static func schedule(_ rest: StrengthRestTimer?, workoutID: UUID, enabled: Bool) {
    let previous = task
    let id = "hybrd.rest." + workoutID.uuidString
    task = Task {
      await previous?.value
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [id])
      guard enabled, let rest, rest.remaining(at: Date()) > 0 else { return }
      let settings = await center.notificationSettings()
      guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
      let remaining = rest.remaining(at: Date())
      guard remaining > 0 else { return }
      let content = UNMutableNotificationContent()
      content.title = "Ready for your next set"
      content.body = rest.exerciseName + " · Your rest timer is complete."
      content.sound = .default
      try? await center.add(UNNotificationRequest(identifier: id, content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)))
    }
  }
}
