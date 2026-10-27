import XCTest
@testable import NoteCore

final class SyncSafetyTests: XCTestCase {
    func testSuccessfulSaveWithLostResponseDoesNotCreateFalseConflict() {
        let base = NoteDocument.cloudEmpty
        var saved = base; saved.addItem("Saved", category: saved.categories[0].id, day: "2026-10-22")
        XCTAssertFalse(NoteSyncRules.hasUnsentCache(base: base, cached: saved, remote: saved))
        XCTAssertFalse(NoteSyncRules.conflicts(local: saved, remote: saved, base: base))
        XCTAssertTrue(NoteSyncRules.hasUnsentCache(base: base, cached: saved, remote: base))
        XCTAssertFalse(NoteSyncRules.conflicts(local: saved, remote: base, base: base))
        var other = base; other.addItem("Other device", category: other.categories[0].id, day: "2026-10-23")
        XCTAssertTrue(NoteSyncRules.conflicts(local: saved, remote: other, base: base))
        XCTAssertFalse(NoteSyncRules.conflicts(local: base, remote: other, base: base))
    }
    func testCompletedRecordsCannotBeRescheduledAccidentally() {
        var item = NoteItem(title: "Keep completion history")
        item.schedule(on: "2026-10-22"); item.toggleCheck(); item.markComplete()
        let before = item; item.schedule(on: "2026-10-23")
        XCTAssertEqual(item, before)
    }
    func testSavedNotesAndNewDirectoryAreOwnerOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("note.json"), file = NoteFile(url: url)
        let note = NoteDocument.cloudEmpty
        try file.save(note)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try file.save(note)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try file.load(), note)
    }
}
