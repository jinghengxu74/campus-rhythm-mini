import Foundation

public enum DailyActionStatus: String, Codable, Equatable {
    case open, done, progress, skipped
}

public struct DailyAction: Codable, Equatable, Identifiable {
    public var id: UUID
    public var day: String
    public var taskTitle: String
    public var step: String
    public var linkedNoteId: UUID?
    public var status: DailyActionStatus
    public var tomorrow: String?
    public init(id: UUID = UUID(), day: String, taskTitle: String, step: String, linkedNoteId: UUID? = nil, status: DailyActionStatus = .open, tomorrow: String? = nil) {
        self.id = id; self.day = day; self.taskTitle = taskTitle; self.step = step; self.linkedNoteId = linkedNoteId; self.status = status; self.tomorrow = tomorrow
    }
}

public struct DailyActionWeek: Equatable {
    public var promised: Int
    public var done: Int
    public var progress: Int
    public var skipped: Int
}

public enum DailyActionRules {
    public static func record(_ action: DailyAction, status: DailyActionStatus) -> DailyAction {
        var next = action
        guard action.status == .open, status != .open else { return action }
        next.status = status
        return next
    }
    public static func taskStaysOpen(after status: DailyActionStatus) -> Bool { status != .open }
    public static func tally(_ actions: [DailyAction], ending day: String) -> DailyActionWeek {
        let start = NoteDay.offset(day, by: -6)
        let window = actions.filter { $0.day >= start && $0.day <= day }
        return DailyActionWeek(
            promised: window.count,
            done: window.filter { $0.status == .done }.count,
            progress: window.filter { $0.status == .progress }.count,
            skipped: window.filter { $0.status == .skipped }.count
        )
    }
}
