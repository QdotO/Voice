import XCTest

@testable import WhisperShared

final class DictationHistoryTests: XCTestCase {
    private var history: DictationHistory!
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        history = DictationHistory(baseURL: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - addEntry

    func testAddEntryStoresEntry() {
        history.addEntry(
            text: "hello world", durationSeconds: 5.0, model: "base.en", outputMethod: "type")
        XCTAssertEqual(history.allEntries().count, 1)
        XCTAssertEqual(history.allEntries().first?.text, "hello world")
    }

    func testAddEntryTrimsWhitespace() {
        history.addEntry(
            text: "  hello  ", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        XCTAssertEqual(history.allEntries().first?.text, "hello")
    }

    func testAddEntryIgnoresEmptyString() {
        history.addEntry(text: "", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        XCTAssertTrue(history.allEntries().isEmpty)
    }

    func testAddEntryIgnoresWhitespaceOnly() {
        history.addEntry(
            text: "   \n\t  ", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        XCTAssertTrue(history.allEntries().isEmpty)
    }

    func testAddEntryPreservesAllFields() {
        history.addEntry(
            text: "test", durationSeconds: 42.5, model: "tiny.en", outputMethod: "paste")
        let entry = history.allEntries().first!
        XCTAssertEqual(entry.text, "test")
        XCTAssertEqual(entry.durationSeconds, 42.5)
        XCTAssertEqual(entry.model, "tiny.en")
        XCTAssertEqual(entry.outputMethod, "paste")
    }

    func testAddEntryExceeding100KeepsLatest100() {
        for i in 0..<150 {
            history.addEntry(
                text: "entry \(i)", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        }
        XCTAssertEqual(history.allEntries().count, 100)
        // Latest entry should still exist
        XCTAssertTrue(history.allEntries().contains { $0.text == "entry 149" })
    }

    // MARK: - allEntries (sorting)

    func testAllEntriesSortedNewestFirst() {
        history.addEntry(
            text: "first", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        // Small delay to ensure timestamp difference
        Thread.sleep(forTimeInterval: 0.01)
        history.addEntry(
            text: "second", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        Thread.sleep(forTimeInterval: 0.01)
        history.addEntry(
            text: "third", durationSeconds: 1.0, model: "base.en", outputMethod: "type")

        let entries = history.allEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].text, "third")
        XCTAssertEqual(entries[1].text, "second")
        XCTAssertEqual(entries[2].text, "first")
    }

    // MARK: - entry(id:)

    func testEntryByIdFindsMatch() {
        history.addEntry(
            text: "findme", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        let added = history.allEntries().first!
        let found = history.entry(id: added.id)
        XCTAssertEqual(found?.text, "findme")
    }

    func testEntryByIdReturnsNilForMissing() {
        XCTAssertNil(history.entry(id: UUID()))
    }

    // MARK: - remove

    func testRemoveDeletesById() {
        history.addEntry(text: "keep", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        history.addEntry(
            text: "delete", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        let toDelete = history.allEntries().first { $0.text == "delete" }!

        history.remove(id: toDelete.id)
        XCTAssertEqual(history.allEntries().count, 1)
        XCTAssertEqual(history.allEntries().first?.text, "keep")
    }

    func testRemoveNonexistentIdNoError() {
        history.addEntry(text: "keep", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        history.remove(id: UUID())
        XCTAssertEqual(history.allEntries().count, 1)
    }

    // MARK: - clear

    func testClearEmptiesHistory() {
        history.addEntry(text: "one", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        history.addEntry(text: "two", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        history.clear()
        XCTAssertTrue(history.allEntries().isEmpty)
    }

    // MARK: - Notifications

    func testAddEntryPostsNotification() {
        let expectation = XCTNSNotificationExpectation(
            name: DictationHistory.didChangeNotification
        )
        history.addEntry(
            text: "notify", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        wait(for: [expectation], timeout: 1.0)
    }

    func testRemovePostsNotification() {
        history.addEntry(
            text: "notify", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        let id = history.allEntries().first!.id

        let expectation = XCTNSNotificationExpectation(
            name: DictationHistory.didChangeNotification
        )
        history.remove(id: id)
        wait(for: [expectation], timeout: 1.0)
    }

    func testClearPostsNotification() {
        history.addEntry(
            text: "notify", durationSeconds: 1.0, model: "base.en", outputMethod: "type")

        let expectation = XCTNSNotificationExpectation(
            name: DictationHistory.didChangeNotification
        )
        history.clear()
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Entry Model

    func testEntryUUIDsAreUnique() {
        history.addEntry(text: "one", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        history.addEntry(text: "two", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        let entries = history.allEntries()
        XCTAssertNotEqual(entries[0].id, entries[1].id)
    }

    func testEntryTimestampIsRecent() {
        let before = Date()
        history.addEntry(
            text: "timed", durationSeconds: 1.0, model: "base.en", outputMethod: "type")
        let after = Date()
        let entry = history.allEntries().first!
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() {
        history.addEntry(
            text: "persist me", durationSeconds: 5.0, model: "base.en", outputMethod: "type")
        let history2 = DictationHistory(baseURL: tempDir)
        XCTAssertEqual(history2.allEntries().count, 1)
        XCTAssertEqual(history2.allEntries().first?.text, "persist me")
    }
}
