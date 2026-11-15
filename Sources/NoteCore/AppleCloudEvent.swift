import Foundation

public struct AppleCloudEventInput: Equatable {
    public let stableKey: String
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let location: String

    public init(stableKey: String, title: String, start: Date, end: Date, allDay: Bool, location: String) {
        self.stableKey = stableKey
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
    }
}

public enum AppleCloudEventCodec {
    private static let prefix = "apple-"

    public static func events(from inputs: [AppleCloudEventInput]) -> [PlanValue] {
        var rows: [PlanValue] = []
        for event in inputs {
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !event.stableKey.isEmpty, !title.isEmpty, event.end > event.start else { continue }
            if event.allDay {
                var day = Calendar.current.startOfDay(for: event.start)
                let end = Calendar.current.startOfDay(for: event.end)
                var count = 0
                while day < end && count < 400 {
                    let key = NoteDay.key(day)
                    rows.append(fields(id: prefix + event.stableKey + "-" + key, sourceID: event.stableKey, title: title, day: key, start: 0, end: 1440, location: event.location))
                    day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
                    count += 1
                }
            } else {
                let zone = TimeZone(identifier: "Asia/Hong_Kong")!
                let day = NoteDay.key(event.start, timeZone: zone)
                let start = NoteDay.minute(event.start, timeZone: zone)
                let duration = max(1, Int((event.end.timeIntervalSince(event.start) / 60).rounded()))
                rows.append(fields(id: prefix + event.stableKey, sourceID: event.stableKey, title: title, day: day, start: start, end: start + duration, location: event.location))
            }
        }
        return rows
    }

    public static func merge(existing: [PlanValue], apple: [PlanValue]) -> [PlanValue] {
        existing.filter { !($0.object?["id"]?.string?.hasPrefix(prefix) ?? false) } + apple
    }

    private static func fields(id: String, sourceID: String, title: String, day: String, start: Int, end: Int, location: String) -> PlanValue {
        .object([
            "id": .string(id),
            "sourceId": .string(sourceID),
            "title": .string(title),
            "date": .string(day),
            "start": .number(Decimal(start)),
            "end": .number(Decimal(end)),
            "location": .string(location),
            "category": .string("Personal"),
            "locked": .bool(true),
        ])
    }
}
