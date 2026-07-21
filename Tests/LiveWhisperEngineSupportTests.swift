import XCTest

@testable import WhisperShared

final class LiveWhisperEngineSupportTests: XCTestCase {
    func testStopBeforePermissionPreventsLaterLaunch() {
        var lifecycle = LiveDictationSessionLifecycle()

        XCTAssertTrue(lifecycle.beginStopping())
        XCTAssertFalse(lifecycle.beginLaunch())
        XCTAssertFalse(lifecycle.hasStartedCapture)
    }

    func testRecordingCallbackAfterStopRequestsImmediateStop() {
        var lifecycle = LiveDictationSessionLifecycle()

        XCTAssertTrue(lifecycle.beginLaunch())
        XCTAssertTrue(lifecycle.beginTranscriberStart())
        XCTAssertTrue(lifecycle.beginStopping())
        XCTAssertTrue(lifecycle.recordingBegan())
        XCTAssertTrue(lifecycle.hasStartedCapture)
    }

    func testCaptureGateDistinguishesStoppedBeforeCaptureFromCapturedSession() {
        var stoppedBeforeCapture = AppOwnedCaptureGate()
        XCTAssertTrue(stoppedBeforeCapture.stop())
        XCTAssertFalse(stoppedBeforeCapture.beginCapture())
        XCTAssertFalse(stoppedBeforeCapture.didBeginCapture)

        var captured = AppOwnedCaptureGate()
        XCTAssertTrue(captured.beginCapture())
        XCTAssertTrue(captured.didBeginCapture)
        XCTAssertTrue(captured.stop())
    }

    func testStopBetweenLaunchAndCaptureStartBlocksCapture() {
        var gate = AppOwnedCaptureGate()

        XCTAssertTrue(gate.stop())
        XCTAssertFalse(gate.beginCapture())
        XCTAssertFalse(gate.stop())
    }

    func testFinalWindowKeepsSubsecondTailAndBoundedContext() {
        let sampleRate = 16_000
        let window = BoundedFinalAudioWindow.make(
            totalSamples: 160_000,
            lastDecodedSamples: 156_000,
            sampleRate: sampleRate
        )

        XCTAssertEqual(window?.range, 124_000..<160_000)
        XCTAssertEqual(window?.decodedSampleCount, 156_000)
    }

    func testFinalWindowIsBoundedForLongSession() {
        let sampleRate = 16_000
        let window = BoundedFinalAudioWindow.make(
            totalSamples: 1_600_000,
            lastDecodedSamples: 1_584_000,
            sampleRate: sampleRate
        )

        XCTAssertEqual(window?.range.count, 48_000)
        XCTAssertLessThanOrEqual(window?.range.count ?? .max, BoundedFinalAudioWindow.maximumSeconds * sampleRate)
    }

    func testFinalWindowSkipsWhenNoResidualAudioExists() {
        XCTAssertNil(
            BoundedFinalAudioWindow.make(
                totalSamples: 48_000,
                lastDecodedSamples: 48_000,
                sampleRate: 16_000
            )
        )
    }

    func testTailMergeAddsOnlyWordsAfterLiveDecodeBoundary() {
        let merged = FinalTailTranscriptMerger.merge(
            currentText: "Turn left at the next light",
            currentWords: [
                TranscriptWord(word: "Turn", start: 0, end: 0.2),
                TranscriptWord(word: "left", start: 0.2, end: 0.4),
                TranscriptWord(word: "at", start: 3.8, end: 4.0),
                TranscriptWord(word: "the", start: 4.0, end: 4.2),
                TranscriptWord(word: "next", start: 4.2, end: 4.4),
                TranscriptWord(word: "light", start: 4.4, end: 4.5),
            ],
            tailText: "the next light and continue",
            tailWords: [
                TranscriptWord(word: "the", start: 4.0, end: 4.2),
                TranscriptWord(word: "next", start: 4.2, end: 4.4),
                TranscriptWord(word: "light", start: 4.4, end: 4.6),
                TranscriptWord(word: "and", start: 4.6, end: 4.8),
                TranscriptWord(word: "continue", start: 4.8, end: 5.1),
            ],
            decodedThroughSeconds: 4.5
        )

        XCTAssertEqual(merged.text, "Turn left at the next light and continue")
        XCTAssertEqual(merged.words.map(\.word), ["Turn", "left", "at", "the", "next", "light", "and", "continue"])
    }
}
