import XCTest
@testable import NoteCore

final class RecommendationsTests: XCTestCase {
    func testBuildFlagsOverdueTask() {
        let tasks = [PlanTaskBrief(id: "a", title: "Essay", dueDate: "2026-10-20", dueTime: 900, duration: 60, done: false, fromCanvas: true)]
        let rows = NoteRecommendationBuilder.build(tasks: tasks, events: [], stickyOpen: 0, day: "2026-10-26", minute: 600)
        XCTAssertTrue(rows.contains { $0.kind == .deadline })
    }

    func testParseTasksIgnoresDone() {
        let plan: [String: PlanValue] = [
            "events": .array([]),
            "tasks": .array([
                .object(["id": .string("1"), "title": .string("Lab"), "dueDate": .string("2026-11-01"), "dueTime": .number(720), "duration": .number(45), "done": .bool(true)])
            ])
        ]
        let parsed = NoteRecommendationBuilder.parseTasks(from: plan)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertTrue(parsed[0].done)
    }
}
