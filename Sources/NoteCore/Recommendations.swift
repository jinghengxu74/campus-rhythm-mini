import Foundation

public struct PlanTaskBrief: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let dueDate: String
    public let dueTime: Int
    public let duration: Int
    public let done: Bool
    public let fromCanvas: Bool
}

public struct NoteRecommendation: Identifiable, Equatable {
    public enum Kind: String, Equatable { case deadline, plan, canvas, sticky, clear }
    public let id: String
    public let title: String
    public let detail: String
    public let reason: String
    public let kind: Kind
}

public enum NoteRecommendationBuilder {
    private static var hkt: TimeZone { TimeZone(identifier: "Asia/Hong_Kong")! }
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = hkt; return c
    }

    public static func parseTasks(from plan: [String: PlanValue]) -> [PlanTaskBrief] {
        guard let rows = plan["tasks"]?.array else { return [] }
        return rows.compactMap { value in
            guard let o = value.object, let id = o["id"]?.string, let title = o["title"]?.string,
                  let dueDate = o["dueDate"]?.string, NoteDay.isValid(dueDate),
                  let dueTime = o["dueTime"]?.number, dueTime.isFinite, dueTime >= 0, dueTime < 1440 else { return nil }
            let duration = max(15, Int((o["duration"]?.number ?? 60).rounded()))
            let done = o["done"] == .bool(true)
            let fromCanvas = o["managedSource"]?.object?["provider"]?.string == "canvas"
            return PlanTaskBrief(id: id, title: title, dueDate: dueDate, dueTime: Int(dueTime), duration: duration, done: done, fromCanvas: fromCanvas)
        }
    }

    public static func build(tasks: [PlanTaskBrief], events: [NoteCalendarEvent], stickyOpen: Int, day: String, minute: Int) -> [NoteRecommendation] {
        var result: [NoteRecommendation] = []
        let open = tasks.filter { !$0.done }.sorted {
            $0.dueDate + String(format: "%04d", $0.dueTime) < $1.dueDate + String(format: "%04d", $1.dueTime)
        }
        let overdue = open.filter { $0.dueDate < day || ($0.dueDate == day && $0.dueTime < minute) }
        if let first = overdue.first {
            let count = overdue.count
            result.append(NoteRecommendation(
                id: "overdue-\(first.id)",
                title: count == 1 ? "Review overdue: \(first.title)" : "Review \(count) overdue deadlines",
                detail: count == 1 ? "Due \(first.dueDate) · \(timeLabel(first.dueTime))" : "Starting with \(first.title)",
                reason: "Past deadlines stay visible until you update or complete them on the web plan.",
                kind: .deadline))
        }
        let soon = open.filter { task in
            guard task.dueDate >= day, let due = NoteDay.date(task.dueDate, timeZone: hkt) else { return false }
            if task.dueDate == day { return task.dueTime >= minute }
            guard let today = NoteDay.date(day, timeZone: hkt), let end = calendar.date(byAdding: .day, value: 3, to: today) else { return false }
            return due <= end
        }
        if let task = soon.first {
            result.append(NoteRecommendation(
                id: "due-\(task.id)",
                title: "Up next: \(task.title)",
                detail: "Due \(task.dueDate) · \(timeLabel(task.dueTime)) · \(task.duration) min work",
                reason: task.fromCanvas ? "Synced from your Canvas-maintained plan." : "From your Campus Rhythm plan.",
                kind: .plan))
        }
        let canvas = open.filter(\.fromCanvas).prefix(2)
        for task in canvas where !result.contains(where: { $0.id == "canvas-\(task.id)" }) {
            result.append(NoteRecommendation(
                id: "canvas-\(task.id)",
                title: "Canvas · \(task.title)",
                detail: "Deadline \(task.dueDate) \(timeLabel(task.dueTime))",
                reason: "Confirm changes on the web if dates moved. Sticky notes sync after you accept.",
                kind: .canvas))
        }
        if stickyOpen > 0 && result.count < 3 {
            result.append(NoteRecommendation(
                id: "sticky-\(day)",
                title: "\(stickyOpen) sticky to-do\(stickyOpen == 1 ? "" : "s") today",
                detail: "Your note list is the execution layer — calendar stays where it is.",
                reason: "Finish or move items in To-do; Pending holds ideas without a date.",
                kind: .sticky))
        }
        if result.isEmpty {
            result.append(NoteRecommendation(
                id: "clear-\(day)",
                title: "You're clear for now",
                detail: "No urgent deadlines in the next few days.",
                reason: "Connect your account and Canvas feed on the web for automatic suggestions.",
                kind: .clear))
        }
        return Array(result.prefix(4))
    }

    private static func timeLabel(_ minute: Int) -> String {
        let h = minute / 60, m = minute % 60
        let period = h >= 12 ? "PM" : "AM"
        let hour = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour, m, period)
    }
}
