import XCTest
@testable import NoteCore

final class TaskDueTextTests: XCTestCase {
    func testChipPartsFormatsWeekdayAndSlashDate() {
        let parts = TaskDueText.chipParts(day: "2026-10-27")
        XCTAssertEqual(parts?.weekdayShort, "Tue")
        XCTAssertEqual(parts?.slashDate, "10/27")
    }

    func testParseStripsAtSuffixIntoDeadlineDay() {
        let draft = TaskDueText.parse("Email @ Mon 26 Oct", referenceDay: "2026-10-27")
        XCTAssertEqual(draft.title, "Email")
        XCTAssertEqual(draft.day, "2026-10-26")
        XCTAssertFalse(draft.monthOnly)
    }

    func testParseMonthOnlyDeadline() {
        let draft = TaskDueText.parse("Writing @ November", referenceDay: "2026-10-27")
        XCTAssertEqual(draft.title, "Writing")
        XCTAssertTrue(draft.monthOnly)
        XCTAssertEqual(draft.day, "2026-11-01")
        XCTAssertEqual(TaskDueText.chipLine(day: draft.day, monthOnly: true), "November")
    }

    func testCanvasWorkIsRecognizedAndLecturesAreNot() {
        XCTAssertTrue(CalendarDeadline.isAssignment("DUE [GBUS 2030] Analytic Write-up"))
        XCTAssertTrue(CalendarDeadline.isAssignment("PRESENT [ISDN 1001] Phase 2 presentation"))
        XCTAssertTrue(CalendarDeadline.isAssignment("Habit Building Challenge: Round 1 Reflection"))
        XCTAssertTrue(CalendarDeadline.isAssignment("Class 7 : required reading [GBUS2050 (L1)]"))
        XCTAssertTrue(CalendarDeadline.isClassSession("ECON 4999Z (L1)"))
        XCTAssertFalse(CalendarDeadline.isClassSession("Class 7 : required reading [GBUS2050 (L1)]"))
        XCTAssertTrue(CalendarDeadline.isHoliday("Recreation Day (TAS)"))
    }
    func testChipLineNilWithoutDeadline() {
        XCTAssertNil(TaskDueText.chipLine(day: nil, monthOnly: false))
    }
    func testClockMinuteReadsCanvasDueTime() {
        XCTAssertEqual(TaskDueText.clockMinute(in: "Due Nov 4 at 11:59pm"), 23 * 60 + 59)
        XCTAssertEqual(TaskDueText.clockMinute(in: "Due at 11:59 p.m."), 23 * 60 + 59)
        XCTAssertEqual(TaskDueText.clockMinute(in: "Submit by 23:59"), 23 * 60 + 59)
        XCTAssertEqual(TaskDueText.badgeLabel(day: "2026-11-04", monthOnly: false, dueMinute: 23 * 60 + 59, today: "2026-10-27"), "Wednesday, 4 November · 23:59 (8 days away)")
        XCTAssertEqual(TaskDueText.badgeLabel(day: "2026-11-20", monthOnly: false, dueMinute: nil, today: "2026-10-27"), "Friday, 20 November (24 days away)")
    }
}
