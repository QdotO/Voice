import XCTest

@testable import WhisperShared

final class DictationPresentationTests: XCTestCase {
    func testPresentationMatrixUsesCanonicalStateCopy() {
        let cases: [(DictationPresentationState, String, DictationSemanticRole)] = [
            (.preparingModel, "Preparing model", .processing),
            (.ready, "Ready", .ready),
            (.listening, "Listening", .active),
            (.transcribing, "Transcribing", .processing),
            (.failure(kind: .unknown, detail: "Decoder stopped"), "Dictation failed", .danger),
        ]

        for (state, title, role) in cases {
            let presentation = DictationStatePresentation(state: state)
            XCTAssertEqual(presentation.title, title)
            XCTAssertEqual(presentation.role, role)
            XCTAssertTrue(presentation.statusItemAccessibilityDescription.contains(title))
        }
    }

    func testFailureClassificationAndRecoveryRouting() {
        XCTAssertEqual(
            DictationStatePresentation.classifyFailure("Accessibility permission not granted"),
            .accessibility
        )
        XCTAssertEqual(
            DictationStatePresentation(state: .failure(kind: .accessibility, detail: "denied"))
                .recoveryAction,
            .openPermissions
        )
        XCTAssertEqual(
            DictationStatePresentation.classifyFailure("Microphone permission was denied"),
            .microphone
        )
        XCTAssertEqual(
            DictationStatePresentation.classifyFailure("Whisper tokenizer is unavailable"),
            .model
        )
        XCTAssertEqual(
            DictationStatePresentation(state: .failure(kind: .model, detail: "failed")).recoveryAction,
            .retry
        )
        XCTAssertEqual(DictationStatePresentation.classifyFailure("Unexpected failure"), .unknown)
    }

    func testLongFailureDetailStaysWithinTwoLines() {
        let rawDetail =
            "first line with enough text to exceed limit\nsecond line\nthird line full accessibility detail"
        let detail = DictationStatePresentation.boundedDetail(
            rawDetail
        )
        XCTAssertLessThanOrEqual(detail.split(separator: "\n").count, 2)
        XCTAssertTrue(detail.contains("…"))
        XCTAssertTrue(
            DictationStatePresentation(state: .failure(kind: .unknown, detail: rawDetail))
                .statusItemAccessibilityDescription.contains(rawDetail)
        )
    }

    func testStopInstructionMatrix() {
        XCTAssertEqual(
            DictationStopInstructionPolicy.instruction(
                trigger: .hotkey,
                capsLockEnabled: true,
                stopHotkeyDisplay: "⌘⌥S"
            ),
            "Press ⌘⌥S to stop"
        )
        XCTAssertEqual(
            DictationStopInstructionPolicy.instruction(
                trigger: .capsLock,
                capsLockEnabled: true,
                stopHotkeyDisplay: "⌘⌥S"
            ),
            "Release Caps Lock to stop"
        )
        XCTAssertEqual(
            DictationStopInstructionPolicy.instruction(
                trigger: .capsLock,
                capsLockEnabled: false,
                stopHotkeyDisplay: "⌘⌥S"
            ),
            "Press ⌘⌥S to stop"
        )
        XCTAssertEqual(
            DictationStopInstructionPolicy.instruction(
                trigger: .ui,
                capsLockEnabled: false,
                stopHotkeyDisplay: nil
            ),
            "Use menu bar to stop"
        )
    }

    func testWaveColorFallbackAndCustomResolution() {
        let custom = FloatingWaveColorResolver.resolve(useCustomColor: true, hex: "#336699")
        XCTAssertFalse(custom.usesFallback)
        XCTAssertEqual(custom.primaryHex, "#336699")
        XCTAssertNotEqual(custom.secondaryHex, custom.primaryHex)

        XCTAssertTrue(FloatingWaveColorResolver.resolve(useCustomColor: true, hex: "bad").usesFallback)
        XCTAssertTrue(FloatingWaveColorResolver.resolve(useCustomColor: false, hex: "#336699").usesFallback)
    }

    func testFloatingIslandWidthIsFixed() {
        XCTAssertEqual(FloatingStatusLayout.islandWidth, 300)
    }
}
