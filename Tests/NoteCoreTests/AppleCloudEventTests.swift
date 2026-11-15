import XCTest
@testable import NoteCore

final class AppleCloudEventTests: XCTestCase {
    func testTimedAppleEventUsesStableIDAndCampusTimeFields() {
        let event = AppleCloudEventInput(
            stableKey: "calendar:event-1", title: "Midterm",
            start: Date(timeIntervalSince1970: 1_792_803_600),
            end: Date(timeIntervalSince1970: 1_792_807_200),
            allDay: false, location: "Room A"
        )
        let rows = AppleCloudEventCodec.events(from: [event])
        XCTAssertEqual(rows.count, 1)
        let fields = rows[0].object!
        XCTAssertEqual(fields["id"]?.string, "apple-calendar:event-1")
        XCTAssertEqual(fields["sourceId"]?.string, "calendar:event-1")
        XCTAssertEqual(fields["date"]?.string, "2026-10-24")
        XCTAssertEqual(fields["start"]?.number, 540)
        XCTAssertEqual(fields["end"]?.number, 600)
        XCTAssertEqual(fields["location"]?.string, "Room A")
        XCTAssertEqual(fields["locked"], .bool(true))
        XCTAssertEqual(AppleCloudEventCodec.events(from: [event]), rows)
    }

    func testAllDaySeriesExpandsWithoutMovingSourceDates() {
        let start = NoteDay.date("2026-10-24")!
        let end = NoteDay.date("2026-10-26")!
        let event = AppleCloudEventInput(stableKey: "calendar:all-day", title: "Reading week", start: start, end: end, allDay: true, location: "")
        let rows = AppleCloudEventCodec.events(from: [event])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map { $0.object!["date"]?.string }, ["2026-10-24", "2026-10-25"])
        XCTAssertEqual(rows.map { $0.object!["id"]?.string }, ["apple-calendar:all-day-2026-10-24", "apple-calendar:all-day-2026-10-25"])
        XCTAssertEqual(rows.map { $0.object!["sourceId"]?.string }, ["calendar:all-day", "calendar:all-day"])
        XCTAssertEqual(rows.map { $0.object!["start"]?.number }, [0, 0])
        XCTAssertEqual(rows.map { $0.object!["end"]?.number }, [1440, 1440])
    }

    func testMergeReplacesOnlyAppleSnapshotsAndKeepsCampusEvents() {
        let campus = PlanValue.object(["id": .string("campus-1"), "title": .string("Class")])
        let oldApple = PlanValue.object(["id": .string("apple-old"), "title": .string("Old")])
        let event = AppleCloudEventInput(stableKey: "calendar:new", title: "New", start: Date(timeIntervalSince1970: 1_792_803_600), end: Date(timeIntervalSince1970: 1_792_807_200), allDay: false, location: "")
        let merged = AppleCloudEventCodec.merge(existing: [campus, oldApple], apple: AppleCloudEventCodec.events(from: [event]))
        XCTAssertEqual(merged.map { $0.object!["id"]?.string }, ["campus-1", "apple-calendar:new"])
        XCTAssertEqual(AppleCloudEventCodec.merge(existing: merged, apple: []), [campus])
    }
}
