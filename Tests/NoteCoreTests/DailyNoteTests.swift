import XCTest
@testable import NoteCore

final class DailyNoteTests: XCTestCase {
    func testTodosCarryForwardAndPendingHasNoDate() {
        var n = NoteDocument(); let group = n.categories[0].id
        let today = n.addItem("Today", category: group, day: "2026-10-22")!
        let tomorrow = n.addItem("Tomorrow", category: group, day: "2026-10-23")!
        let thought = n.addItem("An undated idea", category: group, status: .pending, day: "2026-10-22")!
        XCTAssertEqual(n.items(in: n.categories[0], status: .todo, day: "2026-10-22").map(\.id), [today])
        XCTAssertEqual(n.items(in: n.categories[0], status: .todo, day: "2026-10-23").map(\.id), [today, tomorrow])
        XCTAssertNil(n.categories[0].items.last?.scheduledDay)
        XCTAssertEqual(n.items(in: n.categories[0], status: .pending, day: "2026-10-23").map(\.id), [thought])
        n.editItem(thought) { $0.schedule(on: "2026-10-23") }
        XCTAssertEqual(n.items(in: n.categories[0], status: .todo, day: "2026-10-23").map(\.id), [today, tomorrow, thought])
        n.setStatus(thought, to: .pending); XCTAssertNil(n.categories[0].items.last?.scheduledDay)
    }
    func testCarryForwardPreservesOneRecordAndStopsOnlyAtConfirmation() throws {
        var n = NoteDocument(); let group = n.categories[0].id
        let id = n.addItem("Unfinished", category: group, day: "2026-12-31")!
        n.editItem(id) { $0.highlight = "#FFD966" }
        let original = n
        for day in ["2026-12-31", "2027-01-01", "2028-02-29", "2036-01-01"] {
            XCTAssertEqual(n.items(in: n.categories[0], status: .todo, day: day).map(\.id), [id])
        }
        XCTAssertEqual(n, original, "Viewing later days must not copy or reschedule records")
        XCTAssertTrue(n.items(in: n.categories[0], status: .todo, day: "2026-12-30").isEmpty)
        n.toggleCheck(id)
        XCTAssertEqual(n.items(in: n.categories[0], status: .todo, day: "2027-01-02").count, 1)
        let completed = ISO8601DateFormatter().date(from: "2027-01-02T10:00:00Z")!
        n.markComplete(id, at: completed)
        XCTAssertTrue(n.items(in: n.categories[0], status: .todo, day: "2036-01-01").isEmpty)
        XCTAssertEqual(n.categories[0].items[0].completedAt, completed)
        n.toggleCheck(id)
        XCTAssertEqual(n.items(in: n.categories[0], status: .todo, day: "2027-01-03").map(\.id), [id])
        XCTAssertEqual(n.categories[0].items[0].scheduledDay, "2026-12-31")
        XCTAssertEqual(n.categories[0].items[0].highlight, "#FFD966")
        XCTAssertEqual(try JSONDecoder().decode(NoteDocument.self, from: JSONEncoder().encode(n)), n)
    }
    func testLegacyUndatedTodoRemainsVisibleAndTodayRolloverRespectsOtherWindows() {
        let n = NoteDocument(categories: [NoteCategory(name: "work", items: [NoteItem(title: "Legacy"), NoteItem(title: "Idea", status: .pending), NoteItem(title: "Done", done: true)])])
        XCTAssertEqual(n.items(in: n.categories[0], status: .todo, day: "2027-01-01").map(\.title), ["Legacy"])
        XCTAssertEqual(NoteDay.rollover("2026-12-31", from: "2026-12-31", to: "2027-01-01"), "2027-01-01")
        XCTAssertEqual(NoteDay.rollover("2026-12-30", from: "2026-12-31", to: "2027-01-01"), "2026-12-30")
        XCTAssertEqual(NoteDay.rollover("2027-01-02", from: "2026-12-31", to: "2027-01-01"), "2027-01-02")
    }
    func testMigrationOnlyAddsDayToUndatedOpenTodos() {
        var n = NoteDocument(); let c = n.categories[0].id
        n.addItem("Legacy", category: c); n.addItem("Future", category: c, day: "2026-10-24")
        n.addItem("Pending", category: c, status: .pending); n.addItem("Old done", category: c, status: .completed)
        let ids = n.categories[0].items.map(\.id)
        n.adoptUndatedTodos(on: "2026-10-22")
        XCTAssertEqual(n.categories[0].items.map(\.id), ids)
        XCTAssertEqual(n.categories[0].items.map(\.scheduledDay), ["2026-10-22", "2026-10-24", nil, nil])
        let once = n; n.adoptUndatedTodos(on: "2026-10-23"); XCTAssertEqual(n, once)
        XCTAssertNil(n.categories[0].items.last?.completedAt)
    }
    func testColorHighlightAndDaySurviveOrderingAndDisk() throws {
        var n = NoteDocument(); let a = n.categories[0].id, b = n.categories[1].id
        let id = n.addItem("Important", category: a, day: "2026-10-23")!
        n.editItem(id) { $0.highlight = "#FFD966"; $0.textColor = "#4E91E5" }
        n.reorderItem(id, to: b)
        let file = NoteFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try file.save(n); XCTAssertEqual(try file.load(), n)
        n.editItem(id) { $0.highlight = "invalid" }; XCTAssertFalse(n.isValid)
        XCTAssertThrowsError(try file.save(n))
    }
    func testDateValidationAndCalendarOffsets() {
        XCTAssertFalse(NoteDay.isValid("2026-02-30")); XCTAssertFalse(NoteDay.isValid("Oct 22"))
        XCTAssertEqual(NoteDay.offset("2026-12-31", by: 1), "2027-01-01")
        XCTAssertEqual(NoteDay.offset("2028-02-28", by: 1), "2028-02-29")
        let date = ISO8601DateFormatter().date(from: "2026-10-22T01:00:00Z")!
        XCTAssertEqual(NoteDay.key(date, timeZone: TimeZone(identifier: "America/Los_Angeles")!), "2026-10-21")
        XCTAssertEqual(NoteDay.key(date, timeZone: TimeZone(identifier: "Asia/Hong_Kong")!), "2026-10-22")
    }
    func testCloudEditPreservesEveryUnrelatedPlanField() throws {
        let original: [String: PlanValue] = ["events": .array([]), "tasks": .array([.object(["id": .string("task-prefix-id"), "title": .string("Existing task"), "privateFutureField": .bool(true)])]), "future": .object(["nested": .array([.number(42)])]), "prefs": .object(["bed": .number(1350)])]
        var plan = try NotePlan(fields: original)
        var notebook = try plan.notebook(); let c = notebook.categories[0].id
        notebook.addItem("New note", category: c, day: "2026-10-22"); try plan.setNotebook(notebook)
        for (key, value) in original { XCTAssertEqual(plan.fields[key], value) }
        XCTAssertEqual(try plan.notebook(), notebook)
        let emptyA = try NotePlan(fields: original).notebook(), emptyB = try NotePlan(fields: original).notebook()
        XCTAssertEqual(emptyA, emptyB, "An empty cloud notebook needs stable IDs, otherwise first-save conflict checks fail")
    }
    func testUnrelatedLargeNumbersKeepTheirExactJSONValue() throws {
        let bytes = Data("{\"events\":[],\"tasks\":[],\"futureCounter\":9007199254740993,\"precision\":0.123456789123456789}".utf8)
        let fields = try JSONDecoder().decode([String: PlanValue].self, from: bytes)
        var plan = try NotePlan(fields: fields); try plan.setNotebook(.cloudEmpty)
        let result = String(data: try JSONEncoder().encode(plan.fields), encoding: .utf8)!
        XCTAssertTrue(result.contains("9007199254740993")); XCTAssertTrue(result.contains("0.123456789123456789"))
    }
    func testMalformedCloudNotebookFailsWithoutChangingPlan() throws {
        let fields: [String: PlanValue] = ["events": .array([]), "tasks": .array([]), "notebook": .object(["version": .number(1), "categories": .array([])])]
        let plan = try NotePlan(fields: fields)
        XCTAssertThrowsError(try plan.notebook()); XCTAssertEqual(plan.fields, fields)
        XCTAssertThrowsError(try NotePlan(fields: ["events": .array([])]))
    }
    func testCalendarConvertsCampusTimesAndRetainsAllDayDate() throws {
        let plan = try NotePlan(fields: ["tasks": .array([]), "events": .array([
            .object(["id": .string("class"), "title": .string("Class"), "date": .string("2026-10-22"), "start": .number(540), "end": .number(600)]),
            .object(["id": .string("all-day"), "title": .string("Holiday"), "date": .string("2026-10-22"), "start": .number(0), "end": .number(1440)])
        ])])
        XCTAssertEqual(plan.events.count, 2)
        XCTAssertEqual(plan.events[0].start, ISO8601DateFormatter().date(from: "2026-10-22T01:00:00Z"))
        XCTAssertEqual(plan.events[1].sourceDay, "2026-10-22"); XCTAssertTrue(plan.events[1].allDay)
    }
}
