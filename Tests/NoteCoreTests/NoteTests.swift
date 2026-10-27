import XCTest
@testable import NoteCore

final class NoteTests: XCTestCase {
    func testCustomCategoriesAndPaperStyleCompletionSurviveRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("note.json")
        let file = NoteFile(url: url)
        var note = try file.load()
        let category = note.addCategory("creative projects")!
        let task = note.addItem("  Make a small thing  ", category: category)!
        note.toggleItem(task)
        note.categories[note.categories.count - 1].collapsed = true
        try file.save(note)
        let reopened = try file.load()
        XCTAssertEqual(note, reopened)
        XCTAssertEqual(reopened.categories.last?.items.first?.title, "Make a small thing")
        XCTAssertTrue(reopened.categories.last!.items[0].done)
        XCTAssertTrue(reopened.categories.last!.collapsed)
        XCTAssertEqual(reopened.openCount, 0)
    }
    func testInvalidExistingFileIsNotSilentlyReplaced() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = Data("not a note".utf8); try bytes.write(to: url)
        XCTAssertThrowsError(try NoteFile(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testBlankAndDuplicateCategoryNamesDoNotCreateClutter() {
        var note = NoteDocument()
        XCTAssertNil(note.addCategory(" ")); XCTAssertNil(note.addCategory(" WORK "))
        note.renameCategory(note.categories[0].id, to: "study")
        XCTAssertEqual(note.categories[0].name, "work")
        XCTAssertEqual(note.categories.count, 3)
    }
    func testCheckboxIsReversibleWithoutMovingOrDeletingRows() {
        var note = NoteDocument(); let group = note.categories[0].id
        let a = note.addItem("First", category: group)!, b = note.addItem("Second", category: group)!
        note.toggleItem(a)
        XCTAssertEqual(note.categories[0].items.map(\.id), [a, b]); XCTAssertEqual(note.openCount, 1)
        note.toggleItem(a); XCTAssertEqual(note.openCount, 2)
        XCTAssertFalse(note.categories[0].items[0].done)
    }
    func testAddingToCollapsedCategoryRevealsTheNewTask() {
        var note = NoteDocument(); let id = note.categories[1].id
        note.categories[1].collapsed = true
        XCTAssertNotNil(note.addItem("Book dinner", category: id))
        XCTAssertFalse(note.categories[1].collapsed)
        XCTAssertNil(note.addItem("   ", category: id))
        XCTAssertEqual(note.categories[1].items.count, 1)
    }
    func testInvalidSchemaDoesNotOverwriteLastSavedNote() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = NoteFile(url: url); let good = NoteDocument(); try file.save(good)
        var invalid = good; invalid.categories.removeAll()
        XCTAssertThrowsError(try file.save(invalid)); XCTAssertEqual(try file.load(), good)
    }
    func testExistingBooleanCompletionFilesMigrateWithoutLosingIDsOrText() throws {
        let group = UUID(), active = UUID(), completed = UUID()
        let legacy = """
        {"version":1,"categories":[{"id":"\(group)","name":"work","collapsed":true,"items":[
          {"id":"\(active)","title":"Keep this task","done":false},
          {"id":"\(completed)","title":"Already finished","done":true}
        ]}]}
        """
        let note = try JSONDecoder().decode(NoteDocument.self, from: Data(legacy.utf8))
        XCTAssertTrue(note.isValid)
        XCTAssertEqual(note.categories[0].id, group)
        XCTAssertTrue(note.categories[0].collapsed)
        XCTAssertEqual(note.categories[0].items.map(\.status), [.todo, .completed])
        XCTAssertEqual(note.categories[0].items.map(\.id), [active, completed])
        XCTAssertEqual(note.categories[0].items[0].title, "Keep this task")
        XCTAssertEqual(try JSONDecoder().decode(NoteDocument.self, from: JSONEncoder().encode(note)), note)
    }
    func testFourStatusViewsSeparateTasksAndKeepCategoriesIntact() {
        var note = NoteDocument(); let group = note.categories[0].id
        for status in NoteStatus.allCases { note.addItem(status.title, category: group, status: status) }
        for status in NoteStatus.allCases {
            let rows = note.items(in: note.categories[0], status: status)
            XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].title, status.title)
        }
        XCTAssertEqual(note.openCount, 2)
        XCTAssertEqual(note.categories.count, 3)
    }
    func testCompletingAndReopeningPendingTaskRestoresPendingAfterRelaunch() throws {
        var note = NoteDocument(); let group = note.categories[0].id
        let id = note.addItem("Waiting for feedback", category: group, status: .pending)!
        note.toggleItem(id)
        XCTAssertEqual(note.categories[0].items[0].status, .completed)
        var reopened = try JSONDecoder().decode(NoteDocument.self, from: JSONEncoder().encode(note))
        reopened.toggleItem(id)
        XCTAssertEqual(reopened.categories[0].items[0].status, .pending)
    }
    func testCancellationDoesNotDeleteTaskAndCanBeRestored() {
        var note = NoteDocument(); let group = note.categories[0].id
        let id = note.addItem("Optional errand", category: group)!
        note.setStatus(id, to: .cancelled)
        XCTAssertEqual(note.openCount, 0)
        XCTAssertEqual(note.categories[0].items[0].title, "Optional errand")
        note.setStatus(id, to: .todo)
        XCTAssertEqual(note.openCount, 1)
        XCTAssertEqual(note.categories[0].items[0].id, id)
    }
    func testStatusAndCategoryPersistTogetherOnDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("note.json")
        let file = NoteFile(url: url)
        var note = NoteDocument(); let group = note.addCategory("creative")!
        let id = note.addItem("Choose a cover", category: group)!
        note.setStatus(id, to: .pending); try file.save(note)
        XCTAssertEqual(try file.load(), note)
    }
    func testUnknownStatusDoesNotSilentlyReclassifyExistingTask() throws {
        let data = """
        {"id":"\(UUID())","title":"Keep me","done":false,"status":"unknown"}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(NoteItem.self, from: Data(data.utf8)))
    }
    func testCompletedTaskCanRemainCrossedOutInItsOriginalListWithoutChangingStoredStatus() {
        var note = NoteDocument(); let group = note.categories[0].id
        let id = note.addItem("Finish a draft", category: group)!
        note.toggleItem(id)
        let groupAfter = note.categories[0]
        XCTAssertTrue(note.items(in: groupAfter, status: .todo).isEmpty)
        XCTAssertEqual(note.items(in: groupAfter, status: .todo, completedHere: [id]).map(\.id), [id])
        XCTAssertTrue(note.items(in: groupAfter, status: .todo, completedHere: [id])[0].done)
        XCTAssertEqual(note.items(in: groupAfter, status: .completed).map(\.id), [id])
        XCTAssertEqual(note.openCount, 0)
    }
    func testCategoryReorderMovesTheWholeSectionWithoutChangingItsContents() {
        var note = NoteDocument(); let group = note.categories[2].id
        note.addItem("Read chapter", category: group); note.categories[2].collapsed = true
        let original = note.categories[2]
        note.reorderCategory(group, relativeTo: note.categories[0].id)
        XCTAssertEqual(note.categories[0], original)
        XCTAssertEqual(Set(note.categories.map(\.id)).count, 3)
    }
    func testTaskReorderSupportsBothDirectionsAndPreservesHiddenStatuses() {
        var note = NoteDocument(); let group = note.categories[0].id
        let a = note.addItem("A", category: group)!, pending = note.addItem("Waiting", category: group, status: .pending)!, b = note.addItem("B", category: group)!
        note.reorderItem(b, to: group, relativeTo: a)
        XCTAssertEqual(note.items(in: note.categories[0], status: .todo).map(\.id), [b, a])
        note.reorderItem(b, to: group, relativeTo: a, after: true)
        XCTAssertEqual(note.items(in: note.categories[0], status: .todo).map(\.id), [a, b])
        XCTAssertEqual(note.items(in: note.categories[0], status: .pending).map(\.id), [pending])
        XCTAssertEqual(Set(note.categories[0].items.map(\.id)).count, 3)
    }
    func testCrossCategoryDropPreservesIdentityAndCompletionHistory() {
        var note = NoteDocument(); let work = note.categories[0].id, study = note.categories[2].id
        let id = note.addItem("Waiting for notes", category: work, status: .pending)!
        note.toggleItem(id); let original = note.categories[0].items[0]
        note.categories[2].collapsed = true
        note.reorderItem(id, to: study)
        XCTAssertTrue(note.categories[0].items.isEmpty)
        XCTAssertEqual(note.categories[2].items, [original])
        XCTAssertFalse(note.categories[2].collapsed)
        note.toggleItem(id); XCTAssertEqual(note.categories[2].items[0].status, .pending)
    }
    func testInvalidOrSelfDropCannotRemoveOrDuplicateData() {
        var note = NoteDocument(); let group = note.categories[0].id
        let id = note.addItem("Keep me", category: group)!, before = note
        note.reorderItem(id, to: UUID())
        note.reorderItem(id, to: group, relativeTo: UUID())
        note.reorderItem(id, to: group, relativeTo: id)
        note.reorderCategory(group, relativeTo: UUID())
        note.reorderCategory(group, relativeTo: group)
        XCTAssertEqual(note, before)
    }
    func testDeleteCategoryTrashesTasksAndRequiresAnotherCategory() {
        var note = NoteDocument()
        let extra = note.addCategory("archive")!
        let task = note.addItem("Old", category: extra, status: .todo, day: "2026-10-27")!
        XCTAssertTrue(note.deleteCategory(extra))
        XCTAssertFalse(note.categories.contains(where: { $0.id == extra }))
        XCTAssertEqual(note.trash.count, 1)
        XCTAssertEqual(note.trash[0].item.id, task)
        while note.categories.count > 1 { XCTAssertTrue(note.deleteCategory(note.categories.last!.id)) }
        XCTAssertFalse(note.deleteCategory(note.categories[0].id))
    }
    func testCalendarImportAndDragComplete() {
        var note = NoteDocument()
        let group = note.categories[0].id
        let id = note.importCalendarEvent(key: "cal:evt1", title: "Due essay", category: group, status: .pending, noteDay: nil, dueDay: "2026-10-27")!
        XCTAssertEqual(note.item(withCalendarKey: "cal:evt1")?.id, id)
        XCTAssertNil(note.importCalendarEvent(key: "cal:evt1", title: "Duplicate", category: group, status: .pending, noteDay: nil, dueDay: "2026-10-27"))
        note.completeFromDrag(id)
        XCTAssertTrue(note.categories[0].items.first(where: { $0.id == id })!.done)
    }
    func testRefreshCalendarDeadlineFillsClockOnExistingImport() {
        var note = NoteDocument()
        let group = note.categories[0].id
        let id = note.importCalendarEvent(key: "cal:evt1", title: "Due essay", category: group, status: .pending, noteDay: nil, dueDay: "2026-11-04")!
        XCTAssertNil(note.item(withCalendarKey: "cal:evt1")?.dueMinute)
        note.refreshCalendarDeadline(key: "cal:evt1", dueDay: "2026-11-04", dueMinute: 23 * 60 + 59)
        let item = note.categories[0].items.first { $0.id == id }!
        XCTAssertEqual(item.dueDay, "2026-11-04")
        XCTAssertEqual(item.dueMinute, 23 * 60 + 59)
        XCTAssertEqual(TaskDueText.badgeLabel(day: item.dueDay, monthOnly: item.dueMonthOnly, dueMinute: item.dueMinute, today: "2026-10-27"), "Wednesday, 4 November · 23:59 (8 days away)")
    }
    func testSectionAndTaskPriorityOrderSurviveRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("note.json")
        var note = NoteDocument(); let group = note.categories[2].id
        let a = note.addItem("Earlier", category: group)!, b = note.addItem("First now", category: group)!
        note.reorderItem(b, to: group, relativeTo: a)
        note.reorderCategory(group, relativeTo: note.categories[0].id)
        let file = NoteFile(url: url); try file.save(note)
        let reopened = try file.load()
        XCTAssertEqual(reopened.categories[0].id, group)
        XCTAssertEqual(reopened.categories[0].items.map(\.id), [b, a])
    }
}
