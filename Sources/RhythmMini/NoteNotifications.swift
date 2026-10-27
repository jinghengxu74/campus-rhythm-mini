import Foundation
import NoteCore
import UserNotifications

@MainActor enum NoteNotifications {
    private static let enabledKey = "noteRemindersEnabledV1"
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func requestAccessIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        @unknown default: return false
        }
    }

    static func reconcile(tasks: [PlanTaskBrief]) async {
        guard enabled else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }
        guard await requestAccessIfNeeded() else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let hkt = TimeZone(identifier: "Asia/Hong_Kong")!
        let now = Date()
        var scheduled = 0
        for task in tasks where !task.done {
            guard let noon = NoteDay.date(task.dueDate, timeZone: hkt) else { continue }
            let fire = noon.addingTimeInterval(TimeInterval((task.dueTime - 720) * 60) - 15 * 60)
            guard fire > now, fire.timeIntervalSince(now) < 7 * 86400 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Campus Rhythm · deadline soon"
            content.body = "\(task.title) · due in about 15 minutes"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "task-\(task.id)-\(task.dueDate)-\(task.dueTime)", content: content, trigger: trigger))
            scheduled += 1
            if scheduled >= 24 { break }
        }
    }
}
