import Foundation

public enum NoteStatus: String, Codable, CaseIterable, Identifiable {
    case todo, pending, completed, cancelled
    public static let visibleCases: [NoteStatus] = [.todo, .pending, .completed]
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .todo: return "To-do"
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
    public var isOpen: Bool { self == .todo || self == .pending }
}

public struct NoteItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public private(set) var status: NoteStatus
    public private(set) var isChecked = false
    public private(set) var completedAt: Date?
    public var scheduledDay: String?
    /// Deadline (DDL), independent of which note day the task appears on.
    public var dueDay: String?
    public var dueMonthOnly = false
    public var dueMinute: Int?
    public var textColor: String?
    public var highlight: String?
    public var calendarEventKey: String?
    private var resumeStatus: NoteStatus?
    public var done: Bool { status == .completed }
    public init(id: UUID = UUID(), title: String, done: Bool = false, status: NoteStatus? = nil) {
        self.id = id; self.title = title; self.status = status ?? (done ? .completed : .todo)
    }
    public mutating func setStatus(_ next: NoteStatus, at date: Date = Date()) {
        guard next != status else { return }
        if status.isOpen && !next.isOpen { resumeStatus = status }
        status = next
        if next == .pending { scheduledDay = nil }
        isChecked = false
        completedAt = next == .completed ? Date(timeIntervalSince1970: floor(date.timeIntervalSince1970)) : nil
    }
    public mutating func schedule(on day: String) {
        guard status.isOpen, NoteDay.isValid(day) else { return }
        if status == .pending { setStatus(.todo) }
        scheduledDay = day
    }
    public mutating func setDue(minute: Int?) {
        guard minute == nil || (minute! >= 0 && minute! < 24 * 60) else { return }
        dueMinute = minute
    }
    public mutating func setDeadline(day: String?, monthOnly: Bool = false) {
        if let day {
            guard NoteDay.isValid(day) else { return }
            dueDay = day
            dueMonthOnly = monthOnly
        } else {
            dueDay = nil
            dueMonthOnly = false
        }
    }
    public mutating func clearDeadline() {
        dueDay = nil
        dueMonthOnly = false
        dueMinute = nil
    }
    public mutating func toggleCheck() {
        if done { toggleCompletion() }
        else if status.isOpen { isChecked.toggle() }
    }
    public mutating func markComplete(at date: Date = Date()) {
        guard status.isOpen && isChecked else { return }
        setStatus(.completed, at: date)
    }
    public mutating func completeFromDrag(at date: Date = Date()) {
        guard status.isOpen else { return }
        isChecked = true
        markComplete(at: date)
    }
    public mutating func rescheduleCompletion(to date: Date?) {
        guard status == .completed else { return }
        completedAt = date.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970)) }
    }
    public mutating func toggleCompletion() {
        setStatus(done ? (resumeStatus?.isOpen == true ? resumeStatus! : .todo) : .completed)
    }
    private enum CodingKeys: String, CodingKey { case id, title, done, status, resumeStatus, isChecked, completedAt, scheduledDay, dueDay, dueMonthOnly, dueMinute, textColor, highlight, calendarEventKey }
    public init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        id = try data.decode(UUID.self, forKey: .id)
        title = try data.decode(String.self, forKey: .title)
        if let saved = try data.decodeIfPresent(NoteStatus.self, forKey: .status) { status = saved }
        else { status = try data.decode(Bool.self, forKey: .done) ? .completed : .todo }
        scheduledDay = try data.decodeIfPresent(String.self, forKey: .scheduledDay)
        dueDay = try data.decodeIfPresent(String.self, forKey: .dueDay)
        dueMonthOnly = try data.decodeIfPresent(Bool.self, forKey: .dueMonthOnly) ?? false
        dueMinute = try data.decodeIfPresent(Int.self, forKey: .dueMinute)
        textColor = try data.decodeIfPresent(String.self, forKey: .textColor)
        highlight = try data.decodeIfPresent(String.self, forKey: .highlight)
        calendarEventKey = try data.decodeIfPresent(String.self, forKey: .calendarEventKey)
        resumeStatus = try data.decodeIfPresent(NoteStatus.self, forKey: .resumeStatus)
        isChecked = status.isOpen ? try data.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false : false
        if let timestamp = try data.decodeIfPresent(String.self, forKey: .completedAt) {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let parsed = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) else {
                throw DecodingError.dataCorruptedError(forKey: .completedAt, in: data, debugDescription: "Invalid completion timestamp")
            }
            completedAt = status == .completed ? parsed : nil
        }
    }
    public func encode(to encoder: Encoder) throws {
        var data = encoder.container(keyedBy: CodingKeys.self)
        try data.encode(id, forKey: .id); try data.encode(title, forKey: .title)
        try data.encode(status, forKey: .status); try data.encode(done, forKey: .done)
        try data.encodeIfPresent(resumeStatus, forKey: .resumeStatus)
        try data.encodeIfPresent(scheduledDay, forKey: .scheduledDay)
        try data.encodeIfPresent(dueDay, forKey: .dueDay)
        if dueMonthOnly { try data.encode(dueMonthOnly, forKey: .dueMonthOnly) }
        try data.encodeIfPresent(dueMinute, forKey: .dueMinute)
        try data.encodeIfPresent(textColor, forKey: .textColor)
        try data.encodeIfPresent(highlight, forKey: .highlight)
        try data.encodeIfPresent(calendarEventKey, forKey: .calendarEventKey)
        try data.encode(isChecked, forKey: .isChecked)
        if let completedAt {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try data.encode(formatter.string(from: completedAt), forKey: .completedAt)
        }
    }
}
public struct NoteCategory: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var collapsed: Bool
    public var items: [NoteItem]
    public init(id: UUID = UUID(), name: String, collapsed: Bool = false, items: [NoteItem] = []) { self.id = id; self.name = name; self.collapsed = collapsed; self.items = items }
}
public struct DeletedNoteEntry: Codable, Equatable, Identifiable {
    public var id: UUID { item.id }
    public let item: NoteItem
    public let categoryID: UUID
    public let categoryName: String
    public let deletedAt: Date
}
public struct NoteDocument: Codable, Equatable {
    public var version = 1
    public var categories: [NoteCategory]
    public var trash: [DeletedNoteEntry]
    public init(categories: [NoteCategory] = [NoteCategory(name: "work"), NoteCategory(name: "personal"), NoteCategory(name: "study")], trash: [DeletedNoteEntry] = []) {
        self.categories = categories; self.trash = trash
    }
    private enum CodingKeys: String, CodingKey { case version, categories, trash }
    public init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        version = try data.decodeIfPresent(Int.self, forKey: .version) ?? 1
        categories = try data.decode([NoteCategory].self, forKey: .categories)
        trash = try data.decodeIfPresent([DeletedNoteEntry].self, forKey: .trash) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var data = encoder.container(keyedBy: CodingKeys.self)
        try data.encode(version, forKey: .version)
        try data.encode(categories, forKey: .categories)
        if !trash.isEmpty { try data.encode(trash, forKey: .trash) }
    }
    public static var cloudEmpty: NoteDocument { NoteDocument(categories: [NoteCategory(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, name: "work"), NoteCategory(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, name: "personal"), NoteCategory(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, name: "study")]) }
    public var openCount: Int { categories.flatMap(\.items).filter { $0.status.isOpen }.count }
    public func items(in category: NoteCategory, status: NoteStatus, completedHere: Set<UUID> = [], day: String? = nil) -> [NoteItem] {
        category.items.filter { ($0.status == status || status.isOpen && $0.done && completedHere.contains($0.id)) && (status != .todo || day == nil || NoteDay.includes($0.scheduledDay, on: day!)) }
    }
    public mutating func reorderCategory(_ id: UUID, relativeTo anchor: UUID, after: Bool = false) {
        guard id != anchor, let source = categories.firstIndex(where: { $0.id == id }), categories.contains(where: { $0.id == anchor }) else { return }
        let category = categories.remove(at: source)
        let destination = categories.firstIndex(where: { $0.id == anchor })!
        categories.insert(category, at: destination + (after ? 1 : 0))
    }
    public mutating func reorderItem(_ id: UUID, to category: UUID, relativeTo anchor: UUID? = nil, after: Bool = false) {
        guard anchor != id,
              let destination = categories.firstIndex(where: { $0.id == category }),
              let source = categories.firstIndex(where: { $0.items.contains(where: { $0.id == id }) }),
              let row = categories[source].items.firstIndex(where: { $0.id == id }),
              anchor == nil || categories[destination].items.contains(where: { $0.id == anchor }) else { return }
        let item = categories[source].items.remove(at: row)
        let position = anchor.flatMap { anchor in categories[destination].items.firstIndex(where: { $0.id == anchor }) }.map { $0 + (after ? 1 : 0) } ?? categories[destination].items.count
        categories[destination].items.insert(item, at: position)
        categories[destination].collapsed = false
    }
    public var isValid: Bool {
        let liveIDs = Set(categories.flatMap(\.items).map(\.id))
        let trashIDs = Set(trash.map(\.item.id))
        return version == 1 && !categories.isEmpty && categories.count <= 50 && trash.count <= 80
        && Set(categories.map(\.id)).count == categories.count
        && liveIDs.count == categories.flatMap(\.items).count
        && liveIDs.isDisjoint(with: trashIDs)
        && categories.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 60 && $0.items.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 1000 && ($0.scheduledDay.map(NoteDay.isValid) ?? true) && ($0.dueDay.map(NoteDay.isValid) ?? true) && ($0.textColor.map(NoteDay.isColor) ?? true) && ($0.highlight.map(NoteDay.isColor) ?? true) } }
        && trash.allSatisfy { !$0.categoryName.isEmpty && !$0.item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    @discardableResult public mutating func addCategory(_ value: String) -> UUID? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, categories.count < 50, !categories.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        let category = NoteCategory(name: name); categories.append(category); return category.id
    }
    @discardableResult public mutating func addItem(_ title: String, category id: UUID, status: NoteStatus = .todo, day: String? = nil) -> UUID? {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 1000, let index = categories.firstIndex(where: { $0.id == id }) else { return nil }
        var item = NoteItem(title: value, status: status); if status == .todo, let day { item.schedule(on: day) }; categories[index].items.append(item); categories[index].collapsed = false; return item.id
    }
    public mutating func adoptUndatedTodos(on day: String) {
        guard NoteDay.isValid(day) else { return }
        for c in categories.indices { for i in categories[c].items.indices where categories[c].items[i].status == .todo && categories[c].items[i].scheduledDay == nil { categories[c].items[i].schedule(on: day) } }
    }
    public mutating func editItem(_ id: UUID, _ edit: (inout NoteItem) -> Void) {
        for c in categories.indices { if let i = categories[c].items.firstIndex(where: { $0.id == id }) { edit(&categories[c].items[i]); return } }
    }
    public mutating func toggleItem(_ id: UUID) {
        for category in categories.indices { if let row = categories[category].items.firstIndex(where: { $0.id == id }) { categories[category].items[row].toggleCompletion(); return } }
    }
    public mutating func toggleCheck(_ id: UUID) {
        for category in categories.indices { if let row = categories[category].items.firstIndex(where: { $0.id == id }) { categories[category].items[row].toggleCheck(); return } }
    }
    public mutating func markComplete(_ id: UUID, at date: Date = Date()) {
        for category in categories.indices { if let row = categories[category].items.firstIndex(where: { $0.id == id }) { categories[category].items[row].markComplete(at: date); return } }
    }
    public mutating func completeFromDrag(_ id: UUID, at date: Date = Date()) {
        for category in categories.indices { if let row = categories[category].items.firstIndex(where: { $0.id == id }) { categories[category].items[row].completeFromDrag(at: date); return } }
    }
    public func item(withCalendarKey key: String) -> NoteItem? {
        categories.flatMap(\.items).first { $0.calendarEventKey == key }
    }
    @discardableResult public mutating func importCalendarEvent(key: String, title: String, category id: UUID, status: NoteStatus, noteDay: String?, dueDay: String) -> UUID? {
        guard item(withCalendarKey: key) == nil else { return nil }
        guard let newID = addItem(title, category: id, status: status, day: noteDay) else { return nil }
        editItem(newID) { item in
            item.calendarEventKey = key
            item.setDeadline(day: dueDay, monthOnly: false)
        }
        return newID
    }
    public mutating func reorderCompleted(_ id: UUID, dayID: String, relativeTo anchor: UUID?, after: Bool, calendar: Calendar = .autoupdatingCurrent) {
        guard let location = itemLocation(id), categories[location.category].items[location.row].status == .completed else { return }
        let item = categories[location.category].items[location.row]
        let targetDay = Self.day(fromCompletedDayID: dayID, calendar: calendar)
        func merged(day: Date, time: Date) -> Date {
            var parts = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: day))
            let clock = calendar.dateComponents([.hour, .minute, .second], from: time)
            parts.hour = clock.hour; parts.minute = clock.minute; parts.second = clock.second
            return calendar.date(from: parts) ?? day
        }
        let fallbackClock = item.completedAt ?? calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let nextDate: Date?
        if dayID == CompletedDay.undatedID {
            nextDate = nil
        } else if let anchor, let anchorItem = itemLocation(anchor)?.item, let anchorTime = anchorItem.completedAt {
            let baseDay = targetDay ?? calendar.startOfDay(for: anchorTime)
            nextDate = merged(day: baseDay, time: anchorTime).addingTimeInterval(after ? 30 : -30)
        } else if let targetDay {
            nextDate = merged(day: targetDay, time: fallbackClock)
        } else {
            nextDate = nil
        }
        categories[location.category].items[location.row].rescheduleCompletion(to: nextDate)
    }
    private func itemLocation(_ id: UUID) -> (category: Int, row: Int, item: NoteItem)? {
        for category in categories.indices {
            if let row = categories[category].items.firstIndex(where: { $0.id == id }) {
                return (category, row, categories[category].items[row])
            }
        }
        return nil
    }
    private static func day(fromCompletedDayID dayID: String, calendar: Calendar) -> Date? {
        guard dayID != CompletedDay.undatedID, let interval = TimeInterval(dayID) else { return nil }
        return calendar.startOfDay(for: Date(timeIntervalSince1970: interval))
    }
    public func completedDays(calendar: Calendar = .autoupdatingCurrent) -> [CompletedDay] {
        var groups: [Date: [CompletedEntry]] = [:]
        var undated: [CompletedEntry] = []
        for category in categories {
            for item in category.items where item.done {
                let entry = CompletedEntry(item: item, categoryID: category.id, categoryName: category.name)
                if let date = item.completedAt { groups[calendar.startOfDay(for: date), default: []].append(entry) }
                else { undated.append(entry) }
            }
        }
        var result = groups.keys.sorted(by: >).map { day in
            CompletedDay(day: day, entries: groups[day]!.sorted {
                if $0.item.completedAt == $1.item.completedAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.item.completedAt! > $1.item.completedAt!
            })
        }
        if !undated.isEmpty { result.append(CompletedDay(day: nil, entries: undated)) }
        return result
    }
    public mutating func setStatus(_ id: UUID, to status: NoteStatus) {
        for category in categories.indices { if let row = categories[category].items.firstIndex(where: { $0.id == id }) { categories[category].items[row].setStatus(status); return } }
    }
    public mutating func renameCategory(_ id: UUID, to input: String) {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, !categories.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }), let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
    }
    public mutating func renameItem(_ id: UUID, to input: String) {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 1000 else { return }
        for category in categories.indices { if let row = categories[category].items.firstIndex(where: { $0.id == id }) { categories[category].items[row].title = title; return } }
    }
    @discardableResult public mutating func moveItemToTrash(_ id: UUID, at date: Date = Date()) -> Bool {
        for index in categories.indices {
            guard let row = categories[index].items.firstIndex(where: { $0.id == id }) else { continue }
            let item = categories[index].items.remove(at: row)
            let entry = DeletedNoteEntry(item: item, categoryID: categories[index].id, categoryName: categories[index].name, deletedAt: date)
            trash.insert(entry, at: 0)
            if trash.count > 80 { trash.removeLast(trash.count - 80) }
            return true
        }
        return false
    }
    @discardableResult public mutating func restoreFromTrash(_ id: UUID) -> Bool {
        guard let index = trash.firstIndex(where: { $0.item.id == id }) else { return false }
        let entry = trash.remove(at: index)
        if let category = categories.firstIndex(where: { $0.id == entry.categoryID }) {
            categories[category].items.append(entry.item)
            categories[category].collapsed = false
        } else {
            categories.append(NoteCategory(id: entry.categoryID, name: entry.categoryName, items: [entry.item]))
        }
        return true
    }
    public mutating func purgeFromTrash(_ id: UUID) { trash.removeAll { $0.item.id == id } }
    public mutating func emptyTrash() { trash.removeAll() }
    public mutating func migrateEmbeddedDueDates(referenceDay: String) {
        guard NoteDay.isValid(referenceDay) else { return }
        for category in categories.indices {
            for index in categories[category].items.indices where categories[category].items[index].status.isOpen {
                let parsed = TaskDueText.parse(categories[category].items[index].title, referenceDay: referenceDay)
                guard let day = parsed.day else { continue }
                categories[category].items[index].title = parsed.title
                categories[category].items[index].setDeadline(day: day, monthOnly: parsed.monthOnly)
                if let minute = parsed.dueMinute { categories[category].items[index].setDue(minute: minute) }
            }
        }
    }
    /// Copy legacy `scheduledDay` into `dueDay` once, then new saves keep DDL separate from note placement.
    public mutating func migrateDeadlineFields() {
        guard version < 2 else { return }
        for category in categories.indices {
            for index in categories[category].items.indices where categories[category].items[index].status.isOpen {
                if categories[category].items[index].dueDay == nil, let legacy = categories[category].items[index].scheduledDay {
                    categories[category].items[index].dueDay = legacy
                }
            }
        }
        version = 2
    }
}
public struct CompletedEntry: Identifiable {
    public var id: UUID { item.id }
    public let item: NoteItem
    public let categoryID: UUID
    public let categoryName: String
}
public struct CompletedDay: Identifiable {
    public static let undatedID = "undated"
    public var id: String { day.map { String($0.timeIntervalSince1970) } ?? Self.undatedID }
    public let day: Date?
    public let entries: [CompletedEntry]
}
public struct NoteFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> NoteDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return NoteDocument() }
        let document = try JSONDecoder().decode(NoteDocument.self, from: Data(contentsOf: url))
        guard document.isValid else { throw CocoaError(.fileReadCorruptFile) }; return document
    }
    // Retain the previous device-only workspace before replacing it with an account copy.
    public func saveOfflineCopy(_ document: NoteDocument, backupURL: URL) throws {
        guard document.isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try load()
            try NoteFile(url: backupURL).save(previous)
        }
        try save(document)
    }
    public func save(_ document: NoteDocument) throws {
        guard document.isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum NoteDay {
    // A scheduled day is the start of availability, not an expiry or a new copy.
    public static func includes(_ scheduledDay: String?, on day: String) -> Bool {
        guard isValid(day) else { return false }
        return scheduledDay.map { isValid($0) && $0 <= day } ?? true
    }
    public static func rollover(_ selected: String, from previousToday: String, to today: String) -> String {
        selected == previousToday && isValid(today) ? today : selected
    }
    public static func key(_ date: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    public static func date(_ key: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"; f.isLenient = false
        guard let date = f.date(from: key + " 12:00"), Self.key(date, timeZone: timeZone) == key else { return nil }; return date
    }
    public static func isValid(_ key: String) -> Bool { key.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil && date(key) != nil }
    public static func offset(_ key: String, by days: Int) -> String {
        guard let date = date(key), let next = Calendar.autoupdatingCurrent.date(byAdding: .day, value: days, to: date) else { return key }; return self.key(next)
    }
    public static func minute(_ date: Date = Date(), timeZone: TimeZone = TimeZone(identifier: "Asia/Hong_Kong")!) -> Int {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
    public static func isColor(_ value: String) -> Bool { value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }
}
