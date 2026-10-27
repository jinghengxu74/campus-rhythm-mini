import XCTest
@testable import NoteCore

final class DailyActionTests: XCTestCase {
    func testProgressDoesNotCountAsFinishingTheMainTask() {
        let action = DailyAction(day: "2026-10-26", taskTitle: "Complete VI", step: "List 3 questions · 10 min")
        let recorded = DailyActionRules.record(action, status: .progress)
        XCTAssertEqual(recorded.status, .progress)
        XCTAssertEqual(recorded.taskTitle, "Complete VI")
        XCTAssertTrue(DailyActionRules.taskStaysOpen(after: .progress))
        XCTAssertEqual(DailyActionRules.record(recorded, status: .done).status, .progress)
    }
    func testWeekUsesSevenDaysAndDoesNotDoubleCount() {
        let rows = [
            DailyAction(day: "2026-10-18", taskTitle: "A", step: "a", status: .done),
            DailyAction(day: "2026-10-26", taskTitle: "B", step: "b", status: .progress),
            DailyAction(day: "2026-10-26", taskTitle: "B", step: "b2", status: .skipped)
        ]
        let week = DailyActionRules.tally(rows, ending: "2026-10-26")
        XCTAssertEqual(week.promised, 2)
        XCTAssertEqual(week.done, 0)
        XCTAssertEqual(week.progress, 1)
        XCTAssertEqual(week.skipped, 1)
        XCTAssertEqual(DailyActionRules.tally(rows, ending: "2026-10-25").done, 0)
    }
}
