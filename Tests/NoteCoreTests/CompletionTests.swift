import XCTest
@testable import NoteCore

final class CompletionTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testCheckingIsPersistentButDoesNotArchiveUntilConfirmed() throws {
        var note = NoteDocument(); let group = note.categories[0].id
        let id = note.addItem("Write a memo", category: group)!
        note.toggleCheck(id)
        XCTAssertTrue(note.categories[0].items[0].isChecked)
        XCTAssertEqual(note.categories[0].items[0].status, .todo)
        XCTAssertEqual(note.openCount, 1)
        XCTAssertTrue(note.completedDays().isEmpty)
        var reopened = try JSONDecoder().decode(NoteDocument.self, from: JSONEncoder().encode(note))
        XCTAssertEqual(reopened, note)
        let timestamp = date("2026-10-21T15:59:00Z")
        reopened.markComplete(id, at: timestamp)
        XCTAssertEqual(reopened.categories[0].items[0].completedAt, timestamp)
        XCTAssertFalse(reopened.categories[0].items[0].isChecked)
        XCTAssertEqual(reopened.openCount, 0)
        XCTAssertEqual(try JSONDecoder().decode(NoteDocument.self, from: JSONEncoder().encode(reopened)), reopened)
    }

    func testUncheckingAndUnconfirmedMarkDoNotCreateHistory() {
        var note = NoteDocument(); let group = note.categories[0].id
        let id = note.addItem("Keep working", category: group)!
        note.markComplete(id)
        XCTAssertEqual(note.openCount, 1)
        note.toggleCheck(id); note.toggleCheck(id)
        XCTAssertFalse(note.categories[0].items[0].isChecked)
        XCTAssertTrue(note.completedDays().isEmpty)
    }

    func testRepeatedConfirmKeepsOriginalTimestampAndReopeningRestoresPending() throws {
        var note = NoteDocument(); let group = note.categories[0].id
        let id = note.addItem("Wait for notes", category: group, status: .pending)!
        note.toggleCheck(id); note.markComplete(id, at: date("2026-10-21T04:00:00Z"))
        let completed = note
        note.markComplete(id, at: date("2026-10-22T04:00:00Z"))
        XCTAssertEqual(note, completed)
        var reopened = try JSONDecoder().decode(NoteDocument.self, from: JSONEncoder().encode(note))
        reopened.toggleCheck(id)
        XCTAssertEqual(reopened.categories[0].items[0].status, .pending)
        XCTAssertNil(reopened.categories[0].items[0].completedAt)
        XCTAssertFalse(reopened.categories[0].items[0].isChecked)
        XCTAssertTrue(reopened.completedDays().isEmpty)
    }

    func testDoneListsUseActualLocalMidnightAndKeepUnknownDatesSeparate() {
        var note = NoteDocument(); let group = note.categories[0].id
        let yesterday = note.addItem("Title says Oct 30, but done Oct 21", category: group)!
        let today = note.addItem("Title says yesterday, but done Oct 22", category: group)!
        let later = note.addItem("Later today", category: group)!
        let legacy = note.addItem("Legacy completed task", category: group, status: .completed)!
        for (id, stamp) in [(yesterday, "2026-10-21T15:59:59Z"), (today, "2026-10-21T16:00:00Z"), (later, "2026-10-21T17:00:00Z")] {
            note.toggleCheck(id); note.markComplete(id, at: date(stamp))
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let days = note.completedDays(calendar: calendar)
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days[0].day, date("2026-10-21T16:00:00Z"))
        XCTAssertEqual(days[0].entries.map(\.id), [later, today])
        XCTAssertEqual(days[1].entries.map(\.id), [yesterday])
        XCTAssertNil(days[2].day)
        XCTAssertEqual(days[2].entries.map(\.id), [legacy])
    }

    func testHiddenCancelledRecordsRemainStoredAndLegacyDatesAreNotInvented() throws {
        let input = """
        {"version":1,"categories":[{"id":"\(UUID())","name":"work","collapsed":false,"items":[
        {"id":"\(UUID())","title":"Memo Oct 21","done":true,"status":"completed"},
        {"id":"\(UUID())","title":"Retain cancellation","done":false,"status":"cancelled"}]}]}
        """
        let document = try JSONDecoder().decode(NoteDocument.self, from: Data(input.utf8))
        XCTAssertNil(document.categories[0].items[0].completedAt)
        XCTAssertEqual(document.completedDays().first?.entries.count, 1)
        XCTAssertFalse(NoteStatus.visibleCases.contains(.cancelled))
        XCTAssertEqual(try JSONDecoder().decode(NoteDocument.self, from: JSONEncoder().encode(document)), document)
    }

    func testReorderingCheckedTaskDoesNotLoseDraftOrCreateCompletion() {
        var note = NoteDocument(); let work = note.categories[0].id, study = note.categories[2].id
        let id = note.addItem("Still a draft completion", category: work)!
        note.toggleCheck(id); let item = note.categories[0].items[0]
        note.reorderItem(id, to: study)
        XCTAssertEqual(note.categories[2].items, [item])
        XCTAssertTrue(note.completedDays().isEmpty)
    }
}
