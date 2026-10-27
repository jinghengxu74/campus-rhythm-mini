import XCTest
@testable import NoteCore

final class CompletedChartWindowTests: XCTestCase {
    func testScrollMovesTheSevenDayWindowOneDayAtATime() {
        XCTAssertEqual(CompletedChartWindow.endOffset(scrollX: 0, dayWidth: 40), -49)
        XCTAssertEqual(CompletedChartWindow.endOffset(scrollX: 40, dayWidth: 40), -48)
        XCTAssertEqual(CompletedChartWindow.endOffset(scrollX: 80, dayWidth: 40), -47)
        XCTAssertEqual(CompletedChartWindow.endOffset(scrollX: 49 * 40, dayWidth: 40), 0)
    }

    func testFractionalScrollSettlesOnTheNearestDay() {
        XCTAssertEqual(CompletedChartWindow.endOffset(scrollX: 19, dayWidth: 40), -49)
        XCTAssertEqual(CompletedChartWindow.endOffset(scrollX: 21, dayWidth: 40), -48)
    }

    func testInvalidAndOutOfRangeScrollStaysInsideTheChart() {
        XCTAssertEqual(CompletedChartWindow.endOffset(scrollX: -100, dayWidth: 40), -49)
        XCTAssertEqual(CompletedChartWindow.endOffset(scrollX: 100_000, dayWidth: 40), 0)
        XCTAssertEqual(CompletedChartWindow.endOffset(scrollX: 40, dayWidth: 0), -49)
        XCTAssertEqual(CompletedChartWindow.endOffset(scrollX: .nan, dayWidth: 40), -49)
    }
}
