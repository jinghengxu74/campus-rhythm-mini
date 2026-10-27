import XCTest
@testable import NoteCore
final class CalendarDuplicateTests: XCTestCase {
    func testOnlySuggestSameCourseMidtermPlaceholder() {
        XCTAssertTrue(CalendarDuplicate.isExamPlaceholder("EXAM [ECON 4999Z] MIDTERM EXAM — exact date TBA", matching: "ECON 4999z Mid-term"))
        XCTAssertFalse(CalendarDuplicate.isExamPlaceholder("ECON 4999Z MIDTERM TBA", matching: "ECON 4999Z (L1)"))
        XCTAssertFalse(CalendarDuplicate.isExamPlaceholder("ECON 4999Z MIDTERM TBA", matching: "ECON 2034 Mid-term"))
        XCTAssertFalse(CalendarDuplicate.isExamPlaceholder("ECON 4999Z MIDTERM", matching: "ECON 4999Z Mid-term"))
    }
    func testCalendarDayIncludesMorningAndExcludesNextMorning() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let interval = CalendarDuplicate.dayInterval("2026-10-23", calendar: calendar)!
        let morning = ISO8601DateFormatter().date(from: "2026-10-23T02:30:00Z")!
        let nextMorning = ISO8601DateFormatter().date(from: "2026-10-24T02:30:00Z")!
        XCTAssertTrue(interval.contains(morning)); XCTAssertFalse(interval.contains(nextMorning))
        XCTAssertEqual(calendar.component(.hour, from: interval.start), 0)
    }
    func testDayRangeFollowsDSTAndPlaceholderCanSpanDays() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(CalendarDuplicate.dayInterval("2026-03-08", calendar: calendar)!.duration, 23 * 3600)
        XCTAssertEqual(CalendarDuplicate.dayInterval("2026-11-01", calendar: calendar)!.duration, 25 * 3600)
        XCTAssertTrue(CalendarDuplicate.overlaps(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3*86400), otherStart: Date(timeIntervalSince1970: 2*86400), otherEnd: Date(timeIntervalSince1970: 2*86400+3600)))
        XCTAssertFalse(CalendarDuplicate.overlaps(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86400), otherStart: Date(timeIntervalSince1970: 86400), otherEnd: Date(timeIntervalSince1970: 90000)))
    }
}
