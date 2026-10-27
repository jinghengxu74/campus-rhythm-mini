import XCTest
@testable import NoteCore

final class DesktopHandoffTests: XCTestCase {
    struct Fixture: Decodable { let privateKey: String; let state: String; let callback: String; let expected: String }
    private func fixture() throws -> Fixture { try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Bundle.module.url(forResource: "DesktopHandoff", withExtension: "json")!)) }
    private func challenge(_ f: Fixture) throws -> DesktopHandoff { try DesktopHandoff(privateKey: Data(base64Encoded: f.privateKey)!, state: f.state, startedAt: Date(timeIntervalSince1970: 1800000000)) }
    func testRealWebCryptoPacketDecryptsWithNativeCryptoKitAndCannotReplay() throws {
        let f = try fixture(), c = try challenge(f), now = Date(timeIntervalSince1970: 1800000001)
        XCTAssertEqual(String(data: try c.open(URL(string: f.callback)!, now: now), encoding: .utf8), f.expected)
        XCTAssertThrowsError(try c.open(URL(string: f.callback)!, now: now))
    }
    func testExpiredWrongStateWrongOriginAndTamperedPacketsAreRejected() throws {
        let f = try fixture(), now = Date(timeIntervalSince1970: 1800000001)
        XCTAssertThrowsError(try challenge(f).open(URL(string: f.callback)!, now: now.addingTimeInterval(601)))
        XCTAssertThrowsError(try challenge(f).open(URL(string: f.callback.replacingOccurrences(of: f.state, with: "wrong-state"))!, now: now))
        XCTAssertThrowsError(try challenge(f).open(URL(string: f.callback.replacingOccurrences(of: "rhythmnote://auth", with: "https://elsewhere.test"))!, now: now))
        var parts = URLComponents(string: f.callback)!
        var fragment = URLComponents(string: "https://localhost/?" + parts.fragment!)!
        fragment.queryItems = fragment.queryItems!.map { $0.name == "box" ? URLQueryItem(name: "box", value: ($0.value!.first == "A" ? "B" : "A") + String($0.value!.dropFirst())) : $0 }
        parts.fragment = fragment.percentEncodedQuery
        XCTAssertThrowsError(try challenge(f).open(parts.url!, now: now))
    }
    func testCallbackRejectsUnexpectedQueryAndPortWithoutConsumingKey() throws {
        let f = try fixture(), now = Date(timeIntervalSince1970: 1800000001)
        for mutation in ["query", "port"] {
            let c = try challenge(f)
            var parts = URLComponents(string: f.callback)!
            if mutation == "query" { parts.query = "redirect=elsewhere" } else { parts.port = 443 }
            XCTAssertThrowsError(try c.open(parts.url!, now: now))
            XCTAssertEqual(String(data: try c.open(URL(string: f.callback)!, now: now), encoding: .utf8), f.expected)
        }
    }

}
