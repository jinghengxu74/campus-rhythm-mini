import Foundation

public enum SpokenTask {
    public static func title(from speech: String, today: String) -> String {
        let raw = speech.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, NoteDay.isValid(today) else { return raw }
        let lower = raw.lowercased()
        let day = lower.contains("tomorrow") ? NoteDay.offset(today, by: 1) : today
        let when = lower.contains("morning") ? "morning" : lower.contains("afternoon") ? "afternoon" : (lower.contains("evening") || lower.contains("night") ? "evening" : "")
        let eco = lower.contains("econom") || lower.range(of: #"\beco\b"#, options: .regularExpression) != nil
        let meeting = lower.contains("meeting") || lower.contains("meet")
        guard eco || meeting else { return raw }
        let label = [eco ? "Eco" : "", meeting ? "meeting" : "class"].filter { !$0.isEmpty }.joined(separator: " ")
        guard let date = NoteDay.date(day) else { return raw }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "d MMM"
        let pretty = formatter.string(from: date)
        return when.isEmpty ? "\(label) · \(pretty)" : "\(label) · \(pretty), \(when)"
    }
}
