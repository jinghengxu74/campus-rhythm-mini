import XCTest
@testable import NoteCore
final class ManagedSourceTests: XCTestCase {
    func testNoteCompletionUpdatesLinkedPlannerTaskAndRetainsSourceMetadata() throws {
        var notes = NoteDocument.cloudEmpty
        let id = notes.addItem("Reflection", category: notes.categories[0].id, day: "2026-10-26")!
        let link: PlanValue = .object(["provider": .string("canvas"), "noteId": .string(id.uuidString), "uid": .string("assignment-42")])
        let task: PlanValue = .object(["id": .string("task-42"), "done": .bool(false), "managedSource": link, "duration": .number(25)])
        let event: PlanValue = .object(["id": .string("block"), "taskId": .string("task-42")])
        var plan = try NotePlan(fields: ["tasks": .array([task]), "events": .array([event])])
        notes.toggleCheck(id); try plan.setNotebook(notes)
        XCTAssertEqual(plan.fields["tasks"]?.array?[0].object?["done"], .bool(false))
        XCTAssertEqual(plan.fields["events"]?.array?.count, 1)
        notes.markComplete(id); try plan.setNotebook(notes)
        let saved = plan.fields["tasks"]?.array?[0].object
        XCTAssertEqual(saved?["done"], .bool(true)); XCTAssertEqual(saved?["managedSource"], link)
        XCTAssertEqual(saved?["duration"], .number(25)); XCTAssertNotNil(saved?["completedAt"]?.string)
        XCTAssertEqual(saved?["completionPlan"]?.array?.count, 1); XCTAssertEqual(plan.fields["events"]?.array?.count, 0)
        notes.toggleCheck(id); try plan.setNotebook(notes)
        XCTAssertEqual(plan.fields["tasks"]?.array?[0].object?["done"], .bool(false))
        XCTAssertNil(plan.fields["tasks"]?.array?[0].object?["completedAt"])
    }
    func testUnlinkedPlannerTaskIsUnchanged() throws {
        let task: PlanValue = .object(["id": .string("legacy"), "done": .bool(false)])
        var plan = try NotePlan(fields: ["tasks": .array([task]), "events": .array([])])
        try plan.setNotebook(.cloudEmpty)
        XCTAssertEqual(plan.fields["tasks"], .array([task]))
    }
}
