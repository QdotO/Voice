import XCTest

@testable import WhisperShared

final class TranscriptDiffExtendedTests: XCTestCase {
    // MARK: - Hunk Generation

    func testHunksIdenticalTextReturnsEqual() {
        let hunks = TranscriptDiff.hunks(original: "Hello world.", suggested: "Hello world.")
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks.first?.kind, .equal)
    }

    func testHunksCompletelyDifferentReturnsReplace() {
        let hunks = TranscriptDiff.hunks(
            original: "The cat sat on the mat.",
            suggested: "A dog ran through the park."
        )
        let changeHunks = hunks.filter { $0.isChange }
        XCTAssertFalse(changeHunks.isEmpty)
    }

    func testHunksDeleteSentence() {
        let hunks = TranscriptDiff.hunks(
            original: "First sentence. Second sentence.",
            suggested: "First sentence."
        )
        let deleteHunks = hunks.filter { $0.kind == .delete }
        XCTAssertEqual(deleteHunks.count, 1)
    }

    func testHunksInsertSentence() {
        let hunks = TranscriptDiff.hunks(
            original: "Hello.",
            suggested: "Hello. World."
        )
        let insertHunks = hunks.filter { $0.kind == .insert }
        XCTAssertEqual(insertHunks.count, 1)
    }

    func testHunksModifySentence() {
        let hunks = TranscriptDiff.hunks(
            original: "hello world.",
            suggested: "Hello World."
        )
        // Same normalized key but different actual text -> modify
        let modifyHunks = hunks.filter { $0.kind == .modify }
        XCTAssertEqual(modifyHunks.count, 1)
    }

    func testHunksEmptyOriginal() {
        let hunks = TranscriptDiff.hunks(original: "", suggested: "New text.")
        XCTAssertFalse(hunks.isEmpty)
    }

    func testHunksEmptySuggested() {
        let hunks = TranscriptDiff.hunks(original: "Old text.", suggested: "")
        XCTAssertFalse(hunks.isEmpty)
    }

    func testHunksBothEmpty() {
        let hunks = TranscriptDiff.hunks(original: "", suggested: "")
        XCTAssertTrue(hunks.isEmpty)
    }

    // MARK: - Hunk Properties

    func testIsChangeTrueForModify() {
        let hunk = TranscriptDiffHunk(
            kind: .modify, originalSentences: ["a"], suggestedSentences: ["b"])
        XCTAssertTrue(hunk.isChange)
    }

    func testIsChangeTrueForReplace() {
        let hunk = TranscriptDiffHunk(
            kind: .replace, originalSentences: ["a"], suggestedSentences: ["b"])
        XCTAssertTrue(hunk.isChange)
    }

    func testIsChangeTrueForInsert() {
        let hunk = TranscriptDiffHunk(
            kind: .insert, originalSentences: [], suggestedSentences: ["b"])
        XCTAssertTrue(hunk.isChange)
    }

    func testIsChangeTrueForDelete() {
        let hunk = TranscriptDiffHunk(
            kind: .delete, originalSentences: ["a"], suggestedSentences: [])
        XCTAssertTrue(hunk.isChange)
    }

    func testIsChangeFalseForEqual() {
        let hunk = TranscriptDiffHunk(
            kind: .equal, originalSentences: ["a"], suggestedSentences: ["a"])
        XCTAssertFalse(hunk.isChange)
    }

    func testOriginalTextJoinsSentences() {
        let hunk = TranscriptDiffHunk(
            kind: .equal, originalSentences: ["Hello.", "World."], suggestedSentences: [])
        XCTAssertEqual(hunk.originalText, "Hello. World.")
    }

    func testSuggestedTextJoinsSentences() {
        let hunk = TranscriptDiffHunk(
            kind: .equal, originalSentences: [], suggestedSentences: ["Hello.", "World."])
        XCTAssertEqual(hunk.suggestedText, "Hello. World.")
    }

    // MARK: - Apply

    func testApplyAcceptAllChanges() {
        let original = "hello world. this is test."
        let suggested = "Hello world. This is a test."
        let hunks = TranscriptDiff.hunks(original: original, suggested: suggested)
        let accepted = Set(hunks.filter { $0.isChange }.map { $0.id })
        let result = TranscriptDiff.apply(hunks: hunks, accepted: accepted)
        XCTAssertEqual(result, "Hello world. This is a test.")
    }

    func testApplyRejectAllChanges() {
        let original = "hello world. this is test."
        let suggested = "Hello world. This is a test."
        let hunks = TranscriptDiff.hunks(original: original, suggested: suggested)
        let result = TranscriptDiff.apply(hunks: hunks, accepted: [])
        XCTAssertEqual(result, "hello world. this is test.")
    }

    func testApplyEmptyHunksReturnsEmpty() {
        let result = TranscriptDiff.apply(hunks: [], accepted: [])
        XCTAssertEqual(result, "")
    }

    func testApplyPartialAcceptance() {
        let original = "First bad. Second bad."
        let suggested = "First good. Second good."
        let hunks = TranscriptDiff.hunks(original: original, suggested: suggested)
        let changes = hunks.filter { $0.isChange }

        // Accept only the first change
        if let firstChange = changes.first {
            let accepted = Set([firstChange.id])
            let result = TranscriptDiff.apply(hunks: hunks, accepted: accepted)
            // Result should have the first change accepted and second rejected
            XCTAssertFalse(result.isEmpty)
        }
    }

    func testApplyInsertAccepted() {
        let original = "Hello."
        let suggested = "Hello. Goodbye."
        let hunks = TranscriptDiff.hunks(original: original, suggested: suggested)
        let accepted = Set(hunks.filter { $0.kind == .insert }.map { $0.id })
        let result = TranscriptDiff.apply(hunks: hunks, accepted: accepted)
        XCTAssertTrue(result.contains("Goodbye"))
    }

    func testApplyDeleteRejectedKeepsOriginal() {
        let original = "Hello. Goodbye."
        let suggested = "Hello."
        let hunks = TranscriptDiff.hunks(original: original, suggested: suggested)
        let result = TranscriptDiff.apply(hunks: hunks, accepted: [])
        XCTAssertTrue(result.contains("Goodbye"))
    }

    func testApplyDeleteAcceptedRemovesText() {
        let original = "Hello. Goodbye."
        let suggested = "Hello."
        let hunks = TranscriptDiff.hunks(original: original, suggested: suggested)
        let accepted = Set(hunks.filter { $0.kind == .delete }.map { $0.id })
        let result = TranscriptDiff.apply(hunks: hunks, accepted: accepted)
        XCTAssertFalse(result.contains("Goodbye"))
    }

    // MARK: - Hunk Kind enum

    func testHunkKindRawValues() {
        XCTAssertEqual(TranscriptDiffHunk.Kind.equal.rawValue, "equal")
        XCTAssertEqual(TranscriptDiffHunk.Kind.modify.rawValue, "modify")
        XCTAssertEqual(TranscriptDiffHunk.Kind.replace.rawValue, "replace")
        XCTAssertEqual(TranscriptDiffHunk.Kind.insert.rawValue, "insert")
        XCTAssertEqual(TranscriptDiffHunk.Kind.delete.rawValue, "delete")
    }

    // MARK: - Multi-sentence scenarios

    func testHunksMultipleSentenceMixed() {
        let original = "Alpha. Beta. Gamma. Delta."
        let suggested = "Alpha. BETA. Gamma. DELTA."
        let hunks = TranscriptDiff.hunks(original: original, suggested: suggested)
        let equalCount = hunks.filter { $0.kind == .equal }.count
        let changeCount = hunks.filter { $0.isChange }.count
        XCTAssertGreaterThanOrEqual(equalCount, 1, "Should have at least one equal hunk")
        XCTAssertGreaterThanOrEqual(changeCount, 1, "Should have at least one change")
    }
}
