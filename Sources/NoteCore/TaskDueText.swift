import Foundation

public struct TaskDueDraft: Equatable {
    public var title: String
    public var day: String?
    public var monthOnly = false
    public var dueMinute: Int?
    public init(title: String, day: String? = nil, monthOnly: Bool = false, dueMinute: Int? = nil) {
        self.title = title
        self.day = day
        self.monthOnly = monthOnly
        self.dueMinute = dueMinute
    }
}

public enum CalendarDeadline {
    /// Canvas-style work on a calendar: dues, presentations, readings, reflections, write-ups.
    public static func isAssignment(_ title: String) -> Bool {
        let text = title.lowercased()
        let keys = ["due", "deadline", "present", "presentation", "reflection", "required reading", "write-up", "write up", "analytic", "challenge", "assignment", "quiz", "exam", "submit", "upload", "peer evaluation"]
        return keys.contains { text.contains($0) }
    }
    public static func isHoliday(_ title: String) -> Bool {
        let text = title.lowercased()
        return text.contains("public holiday") || text.contains("recreation day") || text.contains("melbourne cup")
    }
    public static func isNoise(_ title: String) -> Bool {
        let text = title.lowercased()
        return isHoliday(title) || text.contains("formula") || text.contains("grand prix")
    }
    /// A repeating class block such as "ECON 4999Z (L1)", not a piece of work.
    public static func isClassSession(_ title: String) -> Bool {
        if isAssignment(title) { return false }
        return title.range(of: #"\([LTlt]\d+\)"#, options: .regularExpression) != nil
    }
}

public enum TaskDueText {
    private static let suffixPattern = #"\s@\s*(.+)$"#

    public static func parse(_ raw: String, referenceDay: String) -> TaskDueDraft {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return TaskDueDraft(title: "") }
        guard let range = trimmed.range(of: suffixPattern, options: .regularExpression) else {
            return TaskDueDraft(title: trimmed)
        }
        let prefix = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(trimmed[range]).replacingOccurrences(of: #"^\s*@\s*"#, with: "", options: .regularExpression)
        let (day, minute, monthOnly) = parseDueSuffix(suffix, referenceDay: referenceDay)
        let title = prefix.isEmpty ? trimmed : prefix
        return TaskDueDraft(title: title, day: day, monthOnly: monthOnly, dueMinute: minute)
    }

    public static func displayTitle(_ raw: String, referenceDay: String) -> String {
        parse(raw, referenceDay: referenceDay).title
    }

    public static func badgeLabel(day: String?, monthOnly: Bool, dueMinute: Int?, today: String = NoteDay.key()) -> String? {
        guard let day, NoteDay.isValid(day), let date = NoteDay.date(day) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = monthOnly ? "MMMM" : "EEEE, d MMMM"
        var label = formatter.string(from: date)
        guard !monthOnly else { return label }
        if let dueMinute, dueMinute >= 0, dueMinute < 24 * 60 {
            label += String(format: " · %d:%02d", dueMinute / 60, dueMinute % 60)
        }
        if let away = dayDistance(from: today, to: day) {
            label += " (" + awayPhrase(away) + ")"
        }
        return label
    }

    private static func dayDistance(from today: String, to day: String) -> Int? {
        guard let start = NoteDay.date(today), let end = NoteDay.date(day) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: start, to: end).day
    }

    private static func awayPhrase(_ days: Int) -> String {
        switch days {
        case 0: return "today"
        case 1: return "1 day away"
        case let count where count > 1: return "\(count) days away"
        case -1: return "1 day ago"
        default: return "\(abs(days)) days ago"
        }
    }

    public struct ChipParts: Equatable {
        public var weekdayShort: String
        public var slashDate: String
    }

    public static func chipParts(day: String?) -> ChipParts? {
        guard let day, NoteDay.isValid(day), let date = NoteDay.date(day) else { return nil }
        let locale = Locale(identifier: "en_US")
        let weekday = DateFormatter(); weekday.locale = locale; weekday.dateFormat = "EEE"
        let slash = DateFormatter(); slash.locale = locale; slash.dateFormat = "M/d"
        return ChipParts(weekdayShort: weekday.string(from: date), slashDate: slash.string(from: date))
    }

    /// Chip text for DDL: `November`, or `Mon 10/27`, or nil when unset.
    /// First clock time in a Canvas title or notes, such as `11:59pm` or `23:59`.
    public static func clockMinute(in text: String) -> Int? {
        let normalized = text
            .replacingOccurrences(of: "a.m.", with: "am", options: .caseInsensitive)
            .replacingOccurrences(of: "p.m.", with: "pm", options: .caseInsensitive)
            .replacingOccurrences(of: "a.m", with: "am", options: .caseInsensitive)
            .replacingOccurrences(of: "p.m", with: "pm", options: .caseInsensitive)
        let pattern = #"\b(\d{1,2}):(\d{2})\s*(am|pm)?\b|\b(\d{1,2})\s*(am|pm)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = normalized as NSString
        let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            if let minute = flexibleClock(ns.substring(with: match.range)) { return minute }
        }
        return nil
    }

    public static func chipLine(day: String?, monthOnly: Bool) -> String? {
        guard let day, NoteDay.isValid(day), let date = NoteDay.date(day) else { return nil }
        let locale = Locale(identifier: "en_US")
        if monthOnly {
            let formatter = DateFormatter(); formatter.locale = locale; formatter.dateFormat = "MMMM"
            return formatter.string(from: date)
        }
        guard let parts = chipParts(day: day) else { return nil }
        return "\(parts.weekdayShort) \(parts.slashDate)"
    }

    private static func parseDueSuffix(_ suffix: String, referenceDay: String) -> (String?, Int?, Bool) {
        let value = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return (nil, nil, false) }
        var datePart = value
        var minute: Int?
        if let timeRange = value.range(of: #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#, options: [.regularExpression, .caseInsensitive]) {
            minute = parseClock(String(value[timeRange]))
            datePart = value.replacingCharacters(in: timeRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let day = parseDayToken(datePart, referenceDay: referenceDay) { return (day, minute, false) }
        if let day = parseMonthToken(datePart, referenceDay: referenceDay) { return (day, minute, true) }
        return (nil, minute, false)
    }

    private static func parseDayToken(_ token: String, referenceDay: String) -> String? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, NoteDay.isValid(referenceDay), let anchor = NoteDay.date(referenceDay) else { return nil }
        let formats = ["EEEE d MMM yyyy", "EEEE d MMM", "EEE d MMM yyyy", "EEE d MMM", "d MMM yyyy", "d MMM", "d/M/yyyy", "M/d/yyyy", "M/d"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        let year = Calendar.autoupdatingCurrent.component(.year, from: anchor)
        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: cleaned) {
                return NoteDay.key(resolveYear(for: parsed, anchor: anchor))
            }
            if !cleaned.contains(where: \.isNumber), let withYear = formatter.date(from: "\(cleaned) \(year)") {
                return NoteDay.key(resolveYear(for: withYear, anchor: anchor))
            }
        }
        return nil
    }

    private static func parseMonthToken(_ token: String, referenceDay: String) -> String? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, NoteDay.isValid(referenceDay), let anchor = NoteDay.date(referenceDay) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        let year = Calendar.autoupdatingCurrent.component(.year, from: anchor)
        for format in ["MMMM", "MMM"] {
            formatter.dateFormat = format
            guard let monthDate = formatter.date(from: cleaned) ?? formatter.date(from: "\(cleaned) \(year)") else { continue }
            let resolved = resolveYear(for: monthDate, anchor: anchor)
            var parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: resolved)
            parts.day = 1
            guard let first = Calendar.autoupdatingCurrent.date(from: parts) else { continue }
            return NoteDay.key(first)
        }
        return nil
    }

    private static func resolveYear(for date: Date, anchor: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let year = calendar.component(.year, from: anchor)
        var parts = calendar.dateComponents([.month, .day], from: date)
        parts.year = year
        guard var resolved = calendar.date(from: parts) else { return date }
        if let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: anchor), resolved < sixMonthsAgo {
            parts.year = year + 1
            resolved = calendar.date(from: parts) ?? resolved
        }
        return resolved
    }

    private static func flexibleClock(_ token: String) -> Int? {
        let lower = token.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let mer = lower.hasSuffix("pm") ? "pm" : (lower.hasSuffix("am") ? "am" : nil)
        let clock = lower.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = clock.split(separator: ":")
        guard let hour = Int(parts[0]) else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? -1) : 0
        guard minute >= 0, minute < 60 else { return nil }
        if let mer {
            guard hour >= 1, hour <= 12 else { return nil }
            var h = hour % 12
            if mer == "pm" { h += 12 }
            return h * 60 + minute
        }
        guard hour >= 0, hour < 24 else { return nil }
        return hour * 60 + minute
    }

    private static func parseClock(_ token: String) -> Int? {
        let lower = token.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = lower.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let clock = parts[0].split(separator: ":")
        guard let hour = Int(clock[0]) else { return nil }
        let minute = clock.count > 1 ? (Int(clock[1]) ?? 0) : 0
        let pm = parts[1] == "pm"
        var h = hour % 12
        if pm { h += 12 }
        if !pm && hour == 12 { h = 0 }
        guard minute >= 0, minute < 60, h >= 0, h < 24 else { return nil }
        return h * 60 + minute
    }
}
