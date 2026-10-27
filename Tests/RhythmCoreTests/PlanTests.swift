import XCTest
@testable import RhythmCore

final class PlanTests: XCTestCase {
    private func event(_ id: String, task: String? = nil, start: Double = 600, end: Double = 625) -> JSONValue {
        var value: [String: JSONValue] = ["id": .string(id), "date": .string("2026-10-22"), "start": .number(start), "end": .number(end), "title": .string("A test work block")]
        if let task { value["taskId"] = .string(task) }
        return .object(value)
    }
    private func plan() -> PlanDocument {
        var value = PlanDocument.empty()
        value.add(title: "Read a chapter", date: "2026-10-22", minutes: 25, category: "School", id: "a")
        value.add(title: "Walk", date: "2026-10-23", minutes: 20, category: "Exercise", id: "b")
        return value
    }
    func testUnknownAccountFieldsSurviveTaskMutationAndRoundTrip() throws {
        var p = plan()
        p.fields["futureClientField"] = .object(["version": .number(19), "enabled": .bool(true), "optional": .null])
        var rows = p.fields["tasks"]!.array
        var a = rows[0].object; a["futureTaskField"] = .string("keep me"); rows[0] = .object(a); p.fields["tasks"] = .array(rows)
        _ = p.complete("a", at: "2026-10-22T02:00:00Z")
        let decoded = try JSONDecoder().decode(PlanDocument.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(p, decoded)
        XCTAssertEqual(decoded.tasks[0].raw["futureTaskField"], .string("keep me"))
        XCTAssertEqual(decoded.fields["futureClientField"]?.object["enabled"], .bool(true))
    }
    func testCompletionRemovesOnlyLinkedWorkAndKeepsHistory() {
        var p = plan(); p.fields["events"] = .array([event("linked", task: "a"), event("other", task: "b")])
        let receipt = p.complete("a", at: "2026-10-22T02:00:00Z")
        XCTAssertEqual(p.events.map { $0.object["id"]?.string }, ["other"])
        XCTAssertEqual(p.tasks[0].raw["completionPlan"]?.array.count, 1)
        XCTAssertTrue(p.tasks[0].done); XCTAssertFalse(p.tasks[1].done)
        XCTAssertEqual(receipt?.events.count, 1)
        XCTAssertNil(p.complete("a", at: "a-later-time"))
        XCTAssertEqual(p.tasks[0].completedAt, "2026-10-22T02:00:00Z")
    }
    func testUndoRestoresOnlySafeLinkedEvents() {
        var p = plan(); p.fields["events"] = .array([event("linked", task: "a"), event("later", task: "a", start: 700, end: 725)])
        let receipt = p.complete("a", at: "2026-10-22T02:00:00Z")!
        p.fields["events"] = .array([event("new-class", start: 610, end: 650)])
        XCTAssertTrue(p.reopen("a", receipt: receipt))
        XCTAssertEqual(p.events.map { $0.object["id"]?.string }, ["new-class", "later"])
        XCTAssertFalse(p.tasks[0].done); XCTAssertEqual(p.tasks[0].completedAt, "")
    }
    func testStaleUndoCannotReopenNewerCompletion() {
        var p = plan(); let before = p.complete("a", at: "old")!
        XCTAssertTrue(p.reopen("a")); _ = p.complete("a", at: "new")
        XCTAssertFalse(p.reopen("a", receipt: before)); XCTAssertTrue(p.tasks[0].done)
    }
    func testQuickAddValidatesAndNeverDuplicatesIDs() {
        var p = PlanDocument.empty()
        p.add(title: "  ", date: "2026-10-22", minutes: 25, category: "School")
        p.add(title: "Invalid day", date: "2026-02-30", minutes: 25, category: "School")
        p.add(title: "Invalid effort", date: "2026-10-22", minutes: 0, category: "School")
        p.add(title: "Unknown category", date: "2026-10-22", minutes: 25, category: "Work")
        XCTAssertTrue(p.tasks.isEmpty)
        p.add(title: "  A real task  ", date: "2026-10-22", minutes: 40, category: "School", id: "one", inputTimeZone: TimeZone(identifier: "Asia/Hong_Kong")!)
        p.add(title: "Duplicate", date: "2026-10-22", minutes: 25, category: "School", id: "one")
        XCTAssertEqual(p.tasks.count, 1); XCTAssertEqual(p.tasks[0].title, "A real task")
        XCTAssertEqual(p.tasks[0].dueTime, 1439); XCTAssertFalse(p.tasks[0].done)
    }
    func testInvalidSnapshotIsNotAccepted() {
        var p = PlanDocument.empty(); XCTAssertTrue(p.isValid)
        p.fields["events"] = .string("not an event array"); XCTAssertFalse(p.isValid)
        p = .empty(); p.fields["tasks"] = .array([.object(["id": .string("a")])]); XCTAssertFalse(p.isValid)
    }
    func testPriorityDoesNotTreatUnknownWeightAsZeroOrResurrectDone() {
        var p = plan()
        let now = p.tasks[0].dueInstant()!.addingTimeInterval(-1800)
        XCTAssertEqual(p.openTasks(now: now).first?.id, "a")
        _ = p.complete("a", at: "2026-10-22T02:00:00Z")
        XCTAssertEqual(p.openTasks(now: now).map(\.id), ["b"])
    }
    func testSampleIsIndependentAndCompletionIsNotInferredFromEffort() {
        let a = PlanDocument.sample(); var b = a
        _ = b.complete(a.tasks[0].id, at: "now")
        XCTAssertFalse(a.tasks[0].done); XCTAssertTrue(b.tasks[0].done)
        XCTAssertTrue(PlanDocument.empty().tasks.isEmpty)
    }
    func testDesktopDueDateIsStoredInExistingHongKongReference() {
        var p = PlanDocument.empty()
        p.add(title: "Travel task", date: "2026-10-22", minutes: 25, category: "Personal", inputTimeZone: TimeZone(identifier: "America/Los_Angeles")!)
        XCTAssertEqual(p.tasks[0].dueDate, "2026-10-23")
        XCTAssertEqual(p.tasks[0].dueTime, 14 * 60 + 59)
        XCTAssertEqual(p.tasks[0].dueInstant(), ISO8601DateFormatter().date(from: "2026-10-23T06:59:00Z"))
    }
}
