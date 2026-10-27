import Foundation
import Combine
import NoteCore

@MainActor final class NoteRepository: ObservableObject {
    static let shared = NoteRepository()
    @Published private(set) var document = NoteDocument()
    @Published var error = ""
    @Published private(set) var canUndo = false
    @Published var events: [NoteCalendarEvent] = []
    var onLocalEdit: (() -> Void)?
    private var previous: NoteDocument?
    private var readFailed = false
    private(set) var owner: String?
    private var file: NoteFile
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CampusRhythmMini", isDirectory: true)
    init() {
        file = NoteFile(url: Self.directory.appendingPathComponent("sticky-note-v1.json"))
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.directory.path)
        } catch {
            readFailed = true; self.error = "Could not secure the local note folder. Existing files are kept; editing is paused."; return
        }
        load()
    }
    private func load() {
        do {
            var loaded = try file.load()
            let before = loaded
            loaded.adoptUndatedTodos(on: NoteDay.key())
            if before != loaded { try file.save(loaded) }
            document = loaded; readFailed = false; error = ""
        } catch { readFailed = true; self.error = "Could not read the note. The original file is kept; editing is paused." }
        previous = nil; canUndo = false
    }
    func change(_ operation: (inout NoteDocument) -> Void) {
        guard !readFailed else { return }
        var next = document; operation(&next); guard next != document else { return }
        do { try file.save(next); previous = document; canUndo = true; document = next; error = ""; onLocalEdit?() }
        catch { self.error = "Could not save. Your previous note is unchanged." }
    }
    func undo() {
        guard let before = previous, !readFailed else { return }
        do { try file.save(before); document = before; previous = nil; canUndo = false; error = ""; onLocalEdit?() }
        catch { self.error = "Could not save the undo. Your note is unchanged." }
    }
    func connect(owner: String, document: NoteDocument, events: [NoteCalendarEvent]) throws {
        guard UUID(uuidString: owner) != nil, document.isValid else { throw NoteAccountError.message("Unsupported account note.") }
        let target = NoteFile(url: Self.directory.appendingPathComponent("account-" + owner + ".json"))
        try target.save(document)
        self.file = target; self.owner = owner; self.document = document; self.events = events; previous = nil; canUndo = false; readFailed = false; error = ""
    }
    func acceptCloud(_ next: NoteDocument, events: [NoteCalendarEvent]) throws {
        guard next.isValid else { throw NoteAccountError.message("The account note format is unsupported. This Mac’s note was kept.") }
        if next != document { try file.save(next); document = next; previous = nil; canUndo = false }
        self.events = events
    }
    func retainCurrentLocally() throws {
        guard !readFailed else { throw NoteAccountError.message("Could not read notes. Sign-out paused to protect your data.") }
        let local = NoteFile(url: Self.directory.appendingPathComponent("sticky-note-v1.json"))
        try local.saveOfflineCopy(document, backupURL: Self.directory.appendingPathComponent("local-before-signout-" + UUID().uuidString + ".json"))
    }
    func disconnect() {
        owner = nil; onLocalEdit = nil; events = []; file = NoteFile(url: Self.directory.appendingPathComponent("sticky-note-v1.json")); load()
    }
    func localDocument() throws -> NoteDocument { try NoteFile(url: Self.directory.appendingPathComponent("sticky-note-v1.json")).load() }
}

enum NoteTab: String, CaseIterable, Identifiable {
    case todo, pending, completed, events, forYou
    var id: String { rawValue }
    var title: String {
        switch self {
        case .todo: return "To-do"
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .events: return "Events"
        case .forYou: return "For You"
        }
    }
    var usesTaskList: Bool { self != .events && self != .forYou }
}

@MainActor final class Workspace: ObservableObject {
    let repository: NoteRepository
    @Published private(set) var document: NoteDocument
    @Published var selectedCategory: UUID?
    @Published var selectedDay: String
    @Published var tab: NoteTab = .todo { didSet { cancelDrag() } }
    @Published var dragging: NoteDrag?
    @Published var dropTarget: NoteDropTarget?
    private var subscriptions = Set<AnyCancellable>()
    var statusFilter: NoteStatus {
        get { tab.usesTaskList ? (NoteStatus(rawValue: tab.rawValue) ?? .todo) : .todo }
        set { if let next = NoteTab(rawValue: newValue.rawValue) { tab = next } }
    }
    func currentRecommendations(planTasks: [PlanTaskBrief], events: [NoteCalendarEvent]) -> [NoteRecommendation] {
        let day = NoteDay.key()
        let minute = NoteDay.minute()
        return NoteRecommendationBuilder.build(tasks: planTasks, events: events, stickyOpen: openCount, day: day, minute: minute)
    }
    var error: String { repository.error }
    var canUndo: Bool { repository.canUndo }
    var categories: [NoteCategory] { document.categories }
    var selectedName: String { categories.first { $0.id == selectedCategory }?.name ?? "work" }
    var openCount: Int { openTodoCount(on: selectedDay) }
    func openTodoCount(on day: String) -> Int {
        categories.reduce(0) { $0 + document.items(in: $1, status: .todo, day: day).count }
    }
    var preferredHeight: CGFloat { min(600, max(380, 175 + CGFloat(categories.count) * 33 + CGFloat(filteredCount) * 33)) }
    var events: [NoteCalendarEvent] {
        guard let noon = NoteDay.date(selectedDay) else { return [] }
        let start = Calendar.autoupdatingCurrent.startOfDay(for: noon), end = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: start)!
        return repository.events.filter { $0.allDay ? $0.sourceDay == selectedDay : $0.start < end && $0.end > start }.sorted { $0.start < $1.start }
    }
    var completedDays: [CompletedDay] { document.completedDays() }
    var trash: [DeletedNoteEntry] { document.trash }
    var filteredCount: Int { categories.reduce(0) { $0 + items(in: $1).count } }
    init(day: String = NoteDay.key(), repository: NoteRepository? = nil) {
        let repository = repository ?? NoteRepository.shared
        self.repository = repository; document = repository.document; selectedDay = day; selectedCategory = document.categories.first?.id
        repository.$document.sink { [weak self] next in
            self?.document = next
            if !next.categories.contains(where: { $0.id == self?.selectedCategory }) { self?.selectedCategory = next.categories.first?.id }
        }.store(in: &subscriptions)
        repository.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
    }
    func items(in category: NoteCategory) -> [NoteItem] { document.items(in: category, status: statusFilter, day: selectedDay) }
    func shiftDay(_ offset: Int) { selectedDay = NoteDay.offset(selectedDay, by: offset) }
    func add(_ title: String) -> Bool {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let category = selectedCategory, !value.isEmpty else { return false }
        let status: NoteStatus = tab == .pending ? .pending : .todo
        let noteDay = status == .todo ? selectedDay : nil
        var added = false
        let before = document
        repository.change { doc in
            added = doc.addItem(value, category: category, status: status, day: noteDay) != nil
        }
        guard document != before, added else { return false }
        if status == .todo || status == .pending { tab = status == .pending ? .pending : .todo }
        return true
    }
    func promotePending(withinDays days: Int) -> Int {
        let today = NoteDay.key(), limit = NoteDay.offset(today, by: days)
        var ids: [UUID] = []
        for item in document.categories.flatMap(\.items) where item.status == .pending {
            if let dated = item.title.range(of: #"20\d{2}-\d{2}-\d{2}"#, options: .regularExpression).map({ String(item.title[$0]) }), dated >= today, dated <= limit { ids.append(item.id) }
        }
        guard !ids.isEmpty else { return 0 }
        repository.change { doc in
            for id in ids { doc.setStatus(id, to: .todo); doc.editItem(id) { $0.schedule(on: today) } }
        }
        return ids.count
    }
    @discardableResult func addCategory(_ name: String) -> Bool {
        var id: UUID?; repository.change { id = $0.addCategory(name) }
        guard let id, categories.contains(where: { $0.id == id }) else { return false }; selectedCategory = id; return true
    }
    func renameCategory(_ id: UUID, _ name: String) { repository.change { $0.renameCategory(id, to: name) } }
    func toggleCategory(_ id: UUID) { repository.change { doc in if let i = doc.categories.firstIndex(where: { $0.id == id }) { doc.categories[i].collapsed.toggle() } } }
    func renameItem(_ id: UUID, _ title: String) { repository.change { $0.renameItem(id, to: title) } }
    func toggle(_ id: UUID) {
        repository.change { doc in
            doc.toggleCheck(id)
            doc.editItem(id) { if $0.status == .todo && $0.scheduledDay == nil { $0.schedule(on: selectedDay) } }
        }
    }
    func markComplete(_ id: UUID) { repository.change { $0.markComplete(id) } }
    func setStatus(_ id: UUID, _ status: NoteStatus) {
        repository.change { doc in doc.setStatus(id, to: status); if status == .todo { doc.editItem(id) { $0.schedule(on: selectedDay) } } }
    }
    func schedule(_ id: UUID, on day: String) { repository.change { $0.editItem(id) { $0.schedule(on: day) } } }
    func setHighlight(_ id: UUID, _ color: String?) { repository.change { $0.editItem(id) { $0.highlight = color } } }
    func setTextColor(_ id: UUID, _ color: String?) { repository.change { $0.editItem(id) { $0.textColor = color } } }
    func reorderCategory(_ id: UUID, relativeTo anchor: UUID, after: Bool = false) { repository.change { $0.reorderCategory(id, relativeTo: anchor, after: after) } }
    func reorderItem(_ id: UUID, to category: UUID, relativeTo anchor: UUID? = nil, after: Bool = false) { repository.change { $0.reorderItem(id, to: category, relativeTo: anchor, after: after) } }
    func reorderCompleted(_ id: UUID, dayID: String, relativeTo anchor: UUID?, after: Bool) { repository.change { $0.reorderCompleted(id, dayID: dayID, relativeTo: anchor, after: after) } }
    func isCompletedTask(_ id: UUID) -> Bool { document.categories.flatMap(\.items).first(where: { $0.id == id })?.status == .completed }
    func firstCompletedEntry(in dayID: String) -> UUID? { completedDays.first(where: { $0.id == dayID })?.entries.first?.id }
    func delete(_ id: UUID) { repository.change { $0.moveItemToTrash(id) } }
    func restoreTrash(_ id: UUID) { repository.change { $0.restoreFromTrash(id) } }
    func purgeTrash(_ id: UUID) { repository.change { $0.purgeFromTrash(id) } }
    func emptyTrash() { repository.change { $0.emptyTrash() } }
    func move(_ id: UUID, to destination: UUID) { reorderItem(id, to: destination) }
    func removeCategory(_ id: UUID) { repository.change { doc in if doc.categories.count > 1 { doc.categories.removeAll { $0.id == id && $0.items.isEmpty } } } }
    func undo() { repository.undo() }
}
