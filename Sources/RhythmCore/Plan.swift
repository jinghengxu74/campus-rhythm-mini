import Foundation

// Preserve fields introduced by the web/iOS client instead of re-encoding a
// smaller desktop schema over the account's complete plan.
public enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    public var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public var string: String { if case .string(let v) = self { return v }; return "" }
    public var number: Double { if case .number(let v) = self { return v }; return 0 }
    public var bool: Bool { if case .bool(let v) = self { return v }; return false }
}

public struct MiniTask: Identifiable, Equatable {
    public let raw: [String: JSONValue]
    public var id: String { raw["id"]?.string ?? "" }
    public var title: String { raw["title"]?.string ?? "" }
    public var category: String { raw["category"]?.string ?? "School" }
    public var dueDate: String { raw["dueDate"]?.string ?? "" }
    public var dueTime: Int { Int(raw["dueTime"]?.number ?? 1440) }
    public var duration: Int { Int(raw["duration"]?.number ?? 0) }
    public var done: Bool { raw["done"]?.bool ?? false }
    public var completedAt: String { raw["completedAt"]?.string ?? "" }
    public func dueInstant() -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!; f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: dueDate), f.string(from: date) == dueDate else { return nil }
        var reference = Calendar(identifier: .gregorian); reference.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        return reference.date(byAdding: .minute, value: dueTime, to: date)
    }
    public func score(now: Date) -> Double {
        let hours = (dueInstant() ?? .distantFuture).timeIntervalSince(now) / 3600
        let verified = raw["weightConfirmed"]?.bool == true && !(raw["weightSource"]?.string ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let weight = raw["weightPercent"]?.number ?? -1
        return (hours < -24 ? -1500 : hours < 0 ? 1100 : hours <= 24 ? 1000 : 0)
          + 720 / (max(0, hours) + 3) + (verified && weight >= 0 && weight <= 100 ? weight / 2 : 12.5)
          + min(120, Double(duration) / 15) + (raw["importance"]?.string == "high" ? 15 : 0)
    }
    public var dueLabel: String {
        guard let instant = dueInstant() else { return "Check due date" }
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(instant) { day = "Today" }
        else if cal.isDateInTomorrow(instant) { day = "Tomorrow" }
        else { let f = DateFormatter(); f.dateFormat = "MMM d"; day = f.string(from: instant) }
        let clock = cal.dateComponents([.hour, .minute], from: instant)
        return day + " · " + String(format: "%02d:%02d", clock.hour ?? 0, clock.minute ?? 0)
    }
}

public struct CompletionReceipt: Equatable {
    public let taskID: String
    public let at: String
    public let events: [JSONValue]
}

public struct PlanDocument: Codable, Equatable {
    public var fields: [String: JSONValue]
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(from decoder: Decoder) throws { fields = try [String: JSONValue](from: decoder) }
    public func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
    public var tasks: [MiniTask] { (fields["tasks"]?.array ?? []).map { MiniTask(raw: $0.object) } }
    public var events: [JSONValue] { fields["events"]?.array ?? [] }
    public var isValid: Bool {
        guard case .array = fields["tasks"], case .array = fields["events"],
              case .object = fields["prefs"], case .object = fields["goals"], case .object = fields["dashboard"] else { return false }
        return tasks.allSatisfy { !$0.id.isEmpty && !$0.title.isEmpty }
    }
    public func openTasks(now: Date = Date()) -> [MiniTask] {
        tasks.filter { !$0.done }.sorted {
            let a = $0.score(now: now), b = $1.score(now: now)
            return a == b ? ($0.dueDate == $1.dueDate ? $0.id < $1.id : $0.dueDate < $1.dueDate) : a > b
        }
    }
    @discardableResult public mutating func complete(_ id: String, at: String) -> CompletionReceipt? {
        guard let task = tasks.first(where: { $0.id == id }), !task.done else { return nil }
        let linked = events.filter { $0.object["taskId"]?.string == id }
        fields["tasks"] = .array(tasks.map { row in
            guard row.id == id else { return .object(row.raw) }
            var raw = row.raw; raw["done"] = .bool(true); raw["completedAt"] = .string(at)
            let old = raw["completionPlan"]?.array ?? []
            raw["completionPlan"] = .array(old + linked.filter { event in !old.contains { $0.object["id"] == event.object["id"] } })
            return .object(raw)
        })
        fields["events"] = .array(events.filter { $0.object["taskId"]?.string != id })
        return CompletionReceipt(taskID: id, at: at, events: linked)
    }
    @discardableResult public mutating func reopen(_ id: String, receipt: CompletionReceipt? = nil) -> Bool {
        guard let task = tasks.first(where: { $0.id == id }), task.done else { return false }
        if let r = receipt, r.taskID != id || r.at != task.completedAt { return false }
        fields["tasks"] = .array(tasks.map { row in
            guard row.id == id else { return .object(row.raw) }
            var raw = row.raw; raw["done"] = .bool(false); raw.removeValue(forKey: "completedAt"); return .object(raw)
        })
        if let r = receipt {
            let current = events
            let safe = r.events.filter { old in
                old.object["taskId"]?.string == id && !current.contains { event in
                    event.object["id"] == old.object["id"] || Self.overlaps(event, old)
                }
            }
            fields["events"] = .array(current + safe)
        }
        return true
    }
    public mutating func add(title: String, date: String, minutes: Int, category: String, id: String = UUID().uuidString, inputTimeZone: TimeZone = .current) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 240, (1...1440).contains(minutes),
              ["School", "Personal", "Exercise"].contains(category), !tasks.contains(where: { $0.id == id }) else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = inputTimeZone; f.dateFormat = "yyyy-MM-dd"
        guard let parsed = f.date(from: date), f.string(from: parsed) == date else { return }
        var local = Calendar(identifier: .gregorian); local.timeZone = inputTimeZone
        guard let instant = local.date(bySettingHour: 23, minute: 59, second: 0, of: parsed) else { return }
        var reference = Calendar(identifier: .gregorian); reference.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let clock = reference.dateComponents([.hour, .minute], from: instant)
        f.timeZone = reference.timeZone
        let storedDate = f.string(from: instant), storedMinute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        var values = fields["tasks"]?.array ?? []
        values.append(.object(["id": .string(id), "title": .string(title), "dueDate": .string(storedDate), "dueTime": .number(Double(storedMinute)), "duration": .number(Double(minutes)), "category": .string(category), "done": .bool(false), "source": .string("Mac companion · manual entry")]))
        fields["tasks"] = .array(values)
    }
    private static func overlaps(_ a: JSONValue, _ b: JSONValue) -> Bool {
        let f = ISO8601DateFormatter()
        guard let da = f.date(from: (a.object["date"]?.string ?? "") + "T00:00:00Z"),
              let db = f.date(from: (b.object["date"]?.string ?? "") + "T00:00:00Z") else { return true }
        return da.timeIntervalSince1970 / 60 + (a.object["start"]?.number ?? 0) < db.timeIntervalSince1970 / 60 + (b.object["end"]?.number ?? 0)
            && db.timeIntervalSince1970 / 60 + (b.object["start"]?.number ?? 0) < da.timeIntervalSince1970 / 60 + (a.object["end"]?.number ?? 0)
    }
    public static func empty() -> PlanDocument {
        PlanDocument(fields: ["tasks": .array([]), "events": .array([]), "goals": .object(["personal": .bool(true), "work": .bool(true), "health": .bool(true), "exercise": .bool(false), "friends": .bool(false)]), "prefs": .object(["bed": .number(1350), "wake": .number(450), "focus": .string("Afternoon"), "block": .number(60)]), "dashboard": .object([:]), "pinnedTaskId": .null, "onboarded": .bool(true), "dayStart": .number(480), "dayEnd": .number(1260), "morning": .number(450)])
    }
    public static func sample() -> PlanDocument {
        var plan = empty(); let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var goals = plan.fields["goals"]!.object; goals["health"] = .bool(false); plan.fields["goals"] = .object(goals)
        let tomorrow = f.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        plan.add(title: "Make a little space for your next idea", date: f.string(from: Date()), minutes: 25, category: "Personal", id: "sample-idea")
        plan.add(title: "Read one chapter, take a few notes", date: tomorrow, minutes: 40, category: "School", id: "sample-read")
        plan.add(title: "A walk before the day gets busy", date: tomorrow, minutes: 20, category: "Exercise", id: "sample-walk")
        return plan
    }
}
