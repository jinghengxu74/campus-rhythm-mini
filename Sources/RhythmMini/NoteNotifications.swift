import Foundation
import NoteCore
import UserNotifications

@MainActor final class NoteNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NoteNotificationRouter()
    var openDay: ((String) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier || response.actionIdentifier == "OPEN_YESTERDAY",
              let day = response.notification.request.content.userInfo["day"] as? String else { return }
        openDay?(day)
    }
}

@MainActor enum NoteNotifications {
    private static let enabledKey = "noteRemindersEnabledV1"
    private static let carryCategory = "CARRY_FORWARD"
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func configure() {
        UNUserNotificationCenter.current().delegate = NoteNotificationRouter.shared
        let open = UNNotificationAction(identifier: "OPEN_YESTERDAY", title: "Review yesterday", options: [.foreground])
        let category = UNNotificationCategory(identifier: carryCategory, actions: [open], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
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

    static func notifyCarriedTodos(from yesterday: String, count: Int) async {
        guard count > 0 else { return }
        guard await requestAccessIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rhythm Note · carried forward"
        let word = count == 1 ? "task" : "tasks"
        content.body = "\(count) open \(word) from yesterday are on today’s list. Tap to review yesterday or mark them done."
        content.sound = .default
        content.categoryIdentifier = carryCategory
        content.userInfo = ["day": yesterday]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = "carry-\(yesterday)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
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
