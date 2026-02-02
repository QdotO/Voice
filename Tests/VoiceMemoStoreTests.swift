import XCTest

@testable import WhisperShared

final class VoiceMemoStoreTests: XCTestCase {
    func testAddUpdateRemoveMemo() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = VoiceMemoStore.makeInDirectory(tempDir)
        XCTAssertTrue(store.allMemos().isEmpty)

        let memo = VoiceMemo(
            title: "Test Memo",
            durationSeconds: 12.3,
            audioFileName: "memo-test.m4a",
            transcript: nil,
            isTranscribing: true
        )
        store.add(memo)

        XCTAssertEqual(store.allMemos().count, 1)

        store.update(id: memo.id) { updated in
            updated.isTranscribing = false
            updated.transcript = "Hello world"
        }

        let updated = try XCTUnwrap(store.allMemos().first)
        XCTAssertEqual(updated.transcript, "Hello world")
        XCTAssertFalse(updated.isTranscribing)

        store.remove(id: memo.id)
        XCTAssertTrue(store.allMemos().isEmpty)
    }
}
