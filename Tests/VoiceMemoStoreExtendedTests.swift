import XCTest

@testable import WhisperShared

final class VoiceMemoStoreExtendedTests: XCTestCase {
    private var store: VoiceMemoStore!
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = VoiceMemoStore.makeInDirectory(tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - allMemos sorting

    func testAllMemosSortedByCreatedAtDescending() throws {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)

        // Add in non-chronological order
        store.add(
            VoiceMemo(
                title: "Middle", createdAt: date2, durationSeconds: 1.0, audioFileName: "b.m4a"))
        store.add(
            VoiceMemo(
                title: "Oldest", createdAt: date1, durationSeconds: 1.0, audioFileName: "a.m4a"))
        store.add(
            VoiceMemo(
                title: "Newest", createdAt: date3, durationSeconds: 1.0, audioFileName: "c.m4a"))

        let memos = store.allMemos()
        XCTAssertEqual(memos[0].title, "Newest")
        XCTAssertEqual(memos[1].title, "Middle")
        XCTAssertEqual(memos[2].title, "Oldest")
    }

    // MARK: - memoURL

    func testMemoURLConstructsCorrectPath() {
        let memo = VoiceMemo(title: "Test", durationSeconds: 1.0, audioFileName: "memo-001.m4a")
        store.add(memo)
        let url = store.memoURL(for: memo)
        XCTAssertTrue(url.lastPathComponent == "memo-001.m4a")
    }

    func testMemoURLUsesMemosDirectory() {
        let memo = VoiceMemo(title: "Test", durationSeconds: 1.0, audioFileName: "test.m4a")
        let url = store.memoURL(for: memo)
        XCTAssertTrue(url.path.contains("voice-memos"))
    }

    // MARK: - directory

    func testDirectoryIsVoiceMemosDir() {
        XCTAssertTrue(store.directory.path.contains("voice-memos"))
    }

    // MARK: - update

    func testUpdateNonexistentIdNoOp() {
        store.add(VoiceMemo(title: "Keep", durationSeconds: 1.0, audioFileName: "keep.m4a"))
        store.update(id: UUID()) { memo in
            memo.title = "Changed"
        }
        XCTAssertEqual(store.allMemos().count, 1)
        XCTAssertEqual(store.allMemos().first?.title, "Keep")
    }

    // MARK: - remove

    func testRemoveNonexistentIdNoOp() {
        store.add(VoiceMemo(title: "Keep", durationSeconds: 1.0, audioFileName: "keep.m4a"))
        store.remove(id: UUID())
        XCTAssertEqual(store.allMemos().count, 1)
    }

    // MARK: - Notifications

    func testAddPostsNotification() {
        let expectation = XCTNSNotificationExpectation(
            name: VoiceMemoStore.didChangeNotification
        )
        store.add(VoiceMemo(title: "Notify", durationSeconds: 1.0, audioFileName: "notify.m4a"))
        wait(for: [expectation], timeout: 1.0)
    }

    func testUpdatePostsNotification() {
        let memo = VoiceMemo(title: "Notify", durationSeconds: 1.0, audioFileName: "notify.m4a")
        store.add(memo)

        let expectation = XCTNSNotificationExpectation(
            name: VoiceMemoStore.didChangeNotification
        )
        store.update(id: memo.id) { m in m.title = "Updated" }
        wait(for: [expectation], timeout: 1.0)
    }

    func testRemovePostsNotification() {
        let memo = VoiceMemo(title: "Notify", durationSeconds: 1.0, audioFileName: "notify.m4a")
        store.add(memo)

        let expectation = XCTNSNotificationExpectation(
            name: VoiceMemoStore.didChangeNotification
        )
        store.remove(id: memo.id)
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Persistence

    func testPersistenceAcrossStoreInstances() throws {
        let memo = VoiceMemo(title: "Persist", durationSeconds: 30.0, audioFileName: "persist.m4a")
        store.add(memo)

        let store2 = VoiceMemoStore.makeInDirectory(tempDir)
        XCTAssertEqual(store2.allMemos().count, 1)
        XCTAssertEqual(store2.allMemos().first?.title, "Persist")
        XCTAssertEqual(store2.allMemos().first?.durationSeconds, 30.0)
    }

    func testEmptyStoreInitiallyEmpty() {
        XCTAssertTrue(store.allMemos().isEmpty)
    }
}
