import XCTest

@testable import WhisperShared

final class StreamingTranscriptAccumulatorTests: XCTestCase {
    func testKeepsLongerPartialWhenFinalSnapshotFallsBehind() {
        let partial = "This is a long dictation that reaches the final spoken phrase."
        let final = "This is a long dictation that reaches"

        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(partial, final),
            partial
        )
    }

    func testAcceptsSnapshotThatExtendsTranscript() {
        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(
                "This is a long dictation",
                "This is a long dictation with its final words"
            ),
            "This is a long dictation with its final words"
        )
    }

    func testAcceptsSingleWordForwardExtension() {
        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete("Hello", "Hello world"),
            "Hello world"
        )
    }

    func testAcceptsMidSentenceRevisionWithForwardProgress() {
        let current = "Please schedule a meeting Tuesday at noon"
        let candidate = "Please schedule the meeting Tuesday at one PM"

        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(current, candidate),
            candidate
        )
    }

    func testAcceptsShorterCorrectedFinalWhenItCarriesNewTailMeaning() {
        let current = "Please schedule a meeting Tuesday at noon in the downtown office"
        let candidate = "Please schedule the meeting Tuesday at one PM"

        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(current, candidate),
            candidate
        )
    }

    func testEmptyFinalSnapshotFallsBackToAccumulatedPartial() {
        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete("keep these words", "   "),
            "keep these words"
        )
    }

    func testFinalFlushAddsTrailingWordsWithoutAppendingExistingTranscriptTwice() {
        let liveSnapshot = "Keep this sentence"
        let flushedSnapshot = "Keep this sentence and final words"

        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(liveSnapshot, flushedSnapshot),
            flushedSnapshot
        )
        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(flushedSnapshot, flushedSnapshot),
            flushedSnapshot
        )
    }

    func testRejectsDivergentLongerSnapshot() {
        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(
                "Turn left at the next light",
                "Turn right at the next light and continue"
            ),
            "Turn left at the next light"
        )
    }

    func testRejectsDuplicatedFullPhrase() {
        let current = "Take the next exit"
        let candidate = "Take the next exit take the next exit"

        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(current, candidate),
            current
        )
    }

    func testRejectsDuplicatedSuffix() {
        let current = "I need to go home"
        let candidate = "I need to go home to go home"

        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(current, candidate),
            current
        )
    }

    func testRejectsUnrelatedLongerSnapshot() {
        let current = "Please schedule a meeting Tuesday at noon"
        let candidate = "Please schedule galaxy manifests with orange thunder tomorrow"

        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(current, candidate),
            current
        )
    }

    func testAcceptsExtensionWithWhitespaceAndCaseChanges() {
        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(
                "Keep this sentence",
                "keep   this sentence and final words"
            ),
            "keep   this sentence and final words"
        )
    }

    func testAcceptsPunctuationCaseAndWhitespaceChangesWithTailExtension() {
        let current = "Meet me, at noon"
        let candidate = "meet   me at noon — tomorrow"

        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(current, candidate),
            candidate
        )
    }

    func testKeepsStaleShorterSnapshot() {
        let current = "Please schedule a meeting Tuesday at noon tomorrow"
        let candidate = "Please schedule a meeting Tuesday at noon"

        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(current, candidate),
            current
        )
    }

    func testAcceptsLargeTranscriptExtensionWithoutDuplicateScanBlowup() {
        let current = (0..<2_000).map { "word\($0)" }.joined(separator: " ")
        let candidate = current + " final words"

        XCTAssertEqual(
            StreamingTranscriptAccumulator.moreComplete(current, candidate),
            candidate
        )
    }
}
