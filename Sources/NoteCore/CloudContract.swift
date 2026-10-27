import Foundation

public enum NoteSyncRules {
    public static func hasUnsentCache(base: NoteDocument?, cached: NoteDocument?, remote: NoteDocument) -> Bool {
        guard let base, let cached else { return false }
        return base != cached && cached != remote
    }
    public static func conflicts(local: NoteDocument, remote: NoteDocument, base: NoteDocument?) -> Bool {
        local != remote && local != base && remote != base
    }
}

public enum PlanValue: Codable, Equatable {
    case object([String: PlanValue]), array([PlanValue]), string(String), number(Decimal), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Decimal.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([PlanValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: PlanValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .object(let x): try c.encode(x); case .array(let x): try c.encode(x); case .string(let x): try c.encode(x); case .number(let x): try c.encode(x); case .bool(let x): try c.encode(x); case .null: try c.encodeNil() }
    }
    public var object: [String: PlanValue]? { if case .object(let x) = self { return x }; return nil }
    public var array: [PlanValue]? { if case .array(let x) = self { return x }; return nil }
    public var string: String? { if case .string(let x) = self { return x }; return nil }
    public var number: Double? { if case .number(let x) = self { return NSDecimalNumber(decimal: x).doubleValue }; return nil }
}
public struct NotePlan: Equatable {
    public var fields: [String: PlanValue]
    public init(fields: [String: PlanValue]) throws {
        guard fields["events"]?.array != nil, fields["tasks"]?.array != nil else { throw CocoaError(.coderReadCorrupt) }; self.fields = fields
    }
    public func notebook() throws -> NoteDocument {
        guard let value = fields["notebook"], value != .null else { return .cloudEmpty }
        let document = try JSONDecoder().decode(NoteDocument.self, from: JSONEncoder().encode(value))
        guard document.isValid else { throw CocoaError(.coderReadCorrupt) }; return document
    }
    public mutating func setNotebook(_ document: NoteDocument) throws {
        guard document.isValid else { throw CocoaError(.coderInvalidValue) }
        fields["notebook"] = try JSONDecoder().decode(PlanValue.self, from: JSONEncoder().encode(document))
        let notes = Dictionary(uniqueKeysWithValues: document.categories.flatMap(\.items).map { ($0.id.uuidString.lowercased(), $0) })
        var completed = Set<String>()
        fields["tasks"] = .array((fields["tasks"]?.array ?? []).map { value in
            guard var task = value.object, let link = task["managedSource"]?.object,
                  link["provider"]?.string == "canvas", let id = link["noteId"]?.string,
                  let note = notes[id.lowercased()], note.status == .todo || note.status == .pending || note.done,
                  task["done"] != .bool(note.done) else { return value }
            task["done"] = .bool(note.done)
            if note.done {
                if let taskID = task["id"]?.string {
                    completed.insert(taskID)
                    let old = task["completionPlan"]?.array ?? []
                    let ids = Set(old.compactMap { $0.object?["id"]?.string })
                    let linked = (fields["events"]?.array ?? []).filter { $0.object?["taskId"]?.string == taskID && !ids.contains($0.object?["id"]?.string ?? "") }
                    task["completionPlan"] = .array(old + linked)
                }
                if let at = note.completedAt { task["completedAt"] = .string(ISO8601DateFormatter().string(from: at)) }
            } else { task.removeValue(forKey: "completedAt") }
            return .object(task)
        })
        fields["events"] = .array((fields["events"]?.array ?? []).filter { !completed.contains($0.object?["taskId"]?.string ?? "") })

    }
    public var events: [NoteCalendarEvent] { fields["events"]!.array!.compactMap(NoteCalendarEvent.init) }
}
public struct NoteCalendarEvent: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let sourceDay: String
    public let start: Date
    public let end: Date
    public let location: String
    public let allDay: Bool
    public var localDay: String { allDay ? sourceDay : NoteDay.key(start) }
    public init?(_ value: PlanValue) {
        guard let o = value.object, let id = o["id"]?.string, let title = o["title"]?.string,
              let day = o["date"]?.string, let a = o["start"]?.number, let b = o["end"]?.number,
              a.isFinite, b.isFinite, a >= 0, a < 1440, b > a, b <= 10080,
              let noon = NoteDay.date(day, timeZone: TimeZone(identifier: "Asia/Hong_Kong")!) else { return nil }
        self.id = id; self.title = title; sourceDay = day; location = o["location"]?.string ?? ""
        allDay = a == 0 && b == 1440
        start = noon.addingTimeInterval((a - 720) * 60); end = noon.addingTimeInterval((b - 720) * 60)
    }
}
