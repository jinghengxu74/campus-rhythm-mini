import Foundation
import NoteCore

@MainActor final class DailyActionStore: ObservableObject {
    static let shared = DailyActionStore()
    @Published private(set) var actions: [DailyAction] = []
    private var url: URL { NoteRepository.directory.appendingPathComponent("daily-actions-v1.json") }
    init() { load() }
    func load() {
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([DailyAction].self, from: data) else { actions = []; return }
        actions = decoded
    }
    func action(on day: String) -> DailyAction? { actions.first { $0.day == day } }
    func start(day: String, taskTitle: String, step: String, noteId: UUID?) {
        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let small = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NoteDay.isValid(day), !title.isEmpty, !small.isEmpty, action(on: day) == nil else { return }
        actions.append(DailyAction(day: day, taskTitle: title, step: small, linkedNoteId: noteId))
        persist()
    }
    func record(_ id: UUID, status: DailyActionStatus) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        let next = DailyActionRules.record(actions[index], status: status)
        guard next != actions[index] else { return }
        actions[index] = next
        persist()
    }
    func confirmTomorrow(after id: UUID, text: String) {
        let step = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = actions.first(where: { $0.id == id }), !step.isEmpty else { return }
        let tomorrow = NoteDay.offset(current.day, by: 1)
        guard action(on: tomorrow) == nil else { return }
        if let index = actions.firstIndex(where: { $0.id == id }) { actions[index].tomorrow = step }
        actions.append(DailyAction(day: tomorrow, taskTitle: current.taskTitle, step: step, linkedNoteId: current.linkedNoteId))
        persist()
    }
    func week(ending day: String) -> DailyActionWeek { DailyActionRules.tally(actions, ending: day) }
    private func persist() {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
