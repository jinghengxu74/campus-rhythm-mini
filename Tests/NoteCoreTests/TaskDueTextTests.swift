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

    func testChipLineNilWithoutDeadline() {
        XCTAssertNil(TaskDueText.chipLine(day: nil, monthOnly: false))
    }
}
