import XCTest
@testable import NoteCore

final class ReleaseUpdateTests: XCTestCase {
    func testVersionComparisonHandlesPrefixesAndNumericSegments() throws {
        XCTAssertTrue(try version("v0.9.58") > version("0.9.57"))
        XCTAssertTrue(try version("0.10.0") > version("0.9.58"))
        XCTAssertEqual(try version("0.9.58"), try version("v0.9.58.0"))
        XCTAssertFalse(try version("0.9.57") > version("0.9.58"))
    }

    func testMalformedVersionsDoNotProduceAnUpdateVersion() {
        XCTAssertNil(NoteReleaseVersion(""))
        XCTAssertNil(NoteReleaseVersion("v0.9.beta"))
        XCTAssertNil(NoteReleaseVersion("0.9.-1"))
        XCTAssertNil(NoteReleaseVersion("0.9.58-beta"))
    }

    func testLatestReleaseDecodingAndUpdateEligibility() throws {
        let data = Data(#"{"tag_name":"v0.9.58","html_url":"https://github.com/jinghengxu74/campus-rhythm-mini/releases/tag/v0.9.58"}"#.utf8)
        let release = try JSONDecoder().decode(LatestNoteRelease.self, from: data)
        XCTAssertEqual(release.tagName, "v0.9.58")
        XCTAssertEqual(release.htmlURL.host, "github.com")
        XCTAssertTrue(release.isNewer(than: try version("0.9.57")))
        XCTAssertFalse(release.isNewer(than: try version("0.9.58")))
    }

    private func version(_ raw: String) throws -> NoteReleaseVersion {
        try XCTUnwrap(NoteReleaseVersion(raw))
    }
}
