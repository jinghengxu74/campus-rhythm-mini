import XCTest
@testable import NoteCore
final class OfflineCopyTests: XCTestCase {
    func testAccountCopyPersistsAndPreviousLocalWorkspaceIsPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let local = NoteFile(url: folder.appendingPathComponent("local.json")), backup = folder.appendingPathComponent("backup.json")
        var previous = NoteDocument.cloudEmpty
        previous.addItem("Local idea", category: previous.categories[0].id, day: "2026-10-24")
        try local.save(previous)
        var account = NoteDocument.cloudEmpty
        account.addItem("Account task", category: account.categories[0].id, day: "2026-10-23")
        try local.saveOfflineCopy(account, backupURL: backup)
        XCTAssertEqual(try local.load(), account)
        XCTAssertEqual(try NoteFile(url: backup).load(), previous)
    }
}
