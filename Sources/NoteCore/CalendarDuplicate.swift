import Foundation

public enum CalendarDuplicate {
    // Calendar ranges use an exclusive end. Midnight matters: noon loses morning events.
    public static func dayInterval(_ day: String, calendar: Calendar = .autoupdatingCurrent) -> DateInterval? {
        guard let date = NoteDay.date(day, timeZone: calendar.timeZone) else { return nil }
        return calendar.dateInterval(of: .day, for: date)
    }
    public static func overlaps(start: Date, end: Date, otherStart: Date, otherEnd: Date) -> Bool {
        start < otherEnd && end > otherStart
    }
    // A suggestion only: never delete or merge events based on their titles.
    public static func isExamPlaceholder(_ placeholder: String, matching timed: String) -> Bool {
        let a = placeholder.uppercased(), b = timed.uppercased()
        guard a.contains("TBA") || a.contains("EXACT DATE") else { return false }
        let pattern = "[A-Z]{4}\\s*[0-9]{4}[A-Z]?"
        guard let range = a.range(of: pattern, options: .regularExpression) else { return false }
        let course = String(a[range]).filter { !$0.isWhitespace }
        let normalized = b.filter { !$0.isWhitespace }
        guard normalized.contains(course) else { return false }
        return (a.contains("MIDTERM") || a.contains("MID-TERM")) && (b.contains("MIDTERM") || b.contains("MID-TERM"))
    }
}
