import XCTest

@testable import WhisperShared

final class TranscriptDiffTests: XCTestCase {
    func testApplyAcceptAllAndRejectAll() {
        let original = "hello world. this is test"
        let suggested = "Hello world. This is a test."

        let hunks = TranscriptDiff.hunks(original: original, suggested: suggested)
        XCTAssertFalse(hunks.isEmpty)

        let accepted = Set(hunks.filter { $0.isChange }.map { $0.id })
        XCTAssertEqual(
            TranscriptDiff.apply(hunks: hunks, accepted: accepted),
            suggested.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        XCTAssertEqual(
            TranscriptDiff.apply(hunks: hunks, accepted: []),
            original.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testInsertSentenceWhenAccepted() {
        let original = "Hello world."
        let suggested = "Hello world. Nice to meet you."

        let hunks = TranscriptDiff.hunks(original: original, suggested: suggested)
        let insertHunks = hunks.filter { $0.kind == .insert }
        XCTAssertEqual(insertHunks.count, 1)

        let accepted = Set(insertHunks.map { $0.id })
        XCTAssertEqual(TranscriptDiff.apply(hunks: hunks, accepted: accepted), suggested)
        XCTAssertEqual(TranscriptDiff.apply(hunks: hunks, accepted: []), original)
    }
}

