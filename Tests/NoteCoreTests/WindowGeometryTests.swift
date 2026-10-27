import CoreGraphics
import XCTest
@testable import NoteCore

final class WindowGeometryTests: XCTestCase {
    let start = CGRect(x: 100, y: 200, width: 400, height: 500)
    let minimum = CGSize(width: 340, height: 300)
    let maximum = CGSize(width: 760, height: 1100)
    func resized(_ edge: NoteResizeEdges, _ delta: CGSize = CGSize(width: 40, height: 30)) -> CGRect {
        NoteWindowGeometry.resized(start, by: delta, edges: edge, minimum: minimum, maximum: maximum)
    }
    func testAllFourEdgesAndFourCornersKeepTheOppositeSideAnchored() {
        for edges: NoteResizeEdges in [.left, .right, .top, .bottom, [.left, .top], [.right, .top], [.left, .bottom], [.right, .bottom]] {
            let frame = resized(edges)
            if edges.contains(.left) { XCTAssertEqual(frame.maxX, start.maxX); XCTAssertEqual(frame.width, 360) }
            else { XCTAssertEqual(frame.minX, start.minX); XCTAssertEqual(frame.width, edges.contains(.right) ? 440 : 400) }
            if edges.contains(.bottom) { XCTAssertEqual(frame.maxY, start.maxY); XCTAssertEqual(frame.height, 470) }
            else { XCTAssertEqual(frame.minY, start.minY); XCTAssertEqual(frame.height, edges.contains(.top) ? 530 : 500) }
        }
    }
    func testMinimumAndMaximumClampWithoutMovingTheOppositeCorner() {
        let small = resized([.left, .bottom], CGSize(width: 5000, height: 5000))
        XCTAssertEqual(small.size, minimum); XCTAssertEqual(small.maxX, start.maxX); XCTAssertEqual(small.maxY, start.maxY)
        let large = resized([.left, .top], CGSize(width: -5000, height: 5000))
        XCTAssertEqual(large.size, maximum); XCTAssertEqual(large.maxX, start.maxX); XCTAssertEqual(large.minY, start.minY)
        XCTAssertEqual(resized([], CGSize(width: 5000, height: 5000)), start)
    }
}
