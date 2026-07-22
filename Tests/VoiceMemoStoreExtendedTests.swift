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

    func testIndependentStoresInterleaveMutationsWithoutLosingRows() {
        let firstStore = VoiceMemoStore.makeInDirectory(tempDir)
        let secondStore = VoiceMemoStore.makeInDirectory(tempDir)
        let firstMemo = VoiceMemo(
            title: "First", createdAt: Date(timeIntervalSince1970: 1), durationSeconds: 1,
            audioFileName: "first.m4a")
        let secondMemo = VoiceMemo(
            title: "Second", createdAt: Date(timeIntervalSince1970: 2), durationSeconds: 2,
            audioFileName: "second.m4a")
        let thirdMemo = VoiceMemo(
            title: "Third", createdAt: Date(timeIntervalSince1970: 3), durationSeconds: 3,
            audioFileName: "third.m4a")
        let notificationCount = LockedSnapshot(0)
        let observer = NotificationCenter.default.addObserver(
            forName: VoiceMemoStore.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount.withValue { $0 += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        firstStore.add(firstMemo)
        secondStore.add(secondMemo)
        firstStore.update(id: secondMemo.id) { $0.title = "Second updated" }
        secondStore.remove(id: firstMemo.id)
        firstStore.add(thirdMemo)
        secondStore.update(id: thirdMemo.id) { $0.title = "Third updated" }
        firstStore.remove(id: UUID())
        secondStore.remove(id: secondMemo.id)

        XCTAssertEqual(notificationCount.read(), 8)
        XCTAssertEqual(firstStore.allMemos().map(\.title), ["Third updated"])
    }

    func testConcurrentAddsToOneStoreRetainRows() async {
        let sharedStore = VoiceMemoStore.makeInDirectory(tempDir)
        let memos = (0..<40).map { index in
            VoiceMemo(
                title: "Memo \(index)",
                createdAt: Date(timeIntervalSince1970: Double(index)),
                durationSeconds: 1,
                audioFileName: "memo-\(index).m4a"
            )
        }

        await withTaskGroup(of: Void.self) { group in
            for memo in memos {
                group.addTask {
                    sharedStore.add(memo)
                }
            }
        }

        let stored = sharedStore.allMemos()
        XCTAssertEqual(stored.count, memos.count)
        XCTAssertEqual(Set(stored.map(\.id)), Set(memos.map(\.id)))
    }

    func testUpdateMissingIdDoesNotPostNotification() {
        let notificationCount = LockedSnapshot(0)
        let observer = NotificationCenter.default.addObserver(
            forName: VoiceMemoStore.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount.withValue { $0 += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.update(id: UUID()) { $0.title = "Unexpected" }

        XCTAssertEqual(notificationCount.read(), 0)
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
