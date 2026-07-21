import XCTest

@testable import WhisperShared

final class CapsLockDictationPolicyTests: XCTestCase {
    func testPressStartsIdleDictationAndReleaseStopsThatSession() {
        var policy = CapsLockDictationPolicy()

        XCTAssertEqual(
            policy.handle(.flagsChanged(isOn: true), isRecording: false),
            .start
        )
        XCTAssertEqual(
            policy.handle(.keyDown, isRecording: false),
            .none
        )
        XCTAssertEqual(
            policy.handle(.flagsChanged(isOn: false), isRecording: true),
            .stop
        )
        XCTAssertEqual(
            policy.handle(.keyUp, isRecording: false),
            .none
        )
    }

    func testPressStopsActiveDictationOnceWithoutRestartOnRelease() {
        var policy = CapsLockDictationPolicy()

        XCTAssertEqual(
            policy.handle(.keyDown, isRecording: true),
            .stop
        )
        XCTAssertEqual(
            policy.handle(.flagsChanged(isOn: true), isRecording: true),
            .none
        )
        XCTAssertEqual(
            policy.handle(.keyUp, isRecording: false),
            .none
        )
        XCTAssertEqual(
            policy.handle(.flagsChanged(isOn: false), isRecording: false),
            .none
        )
    }

    func testNextPressCanStartAfterCompletedPress() {
        var policy = CapsLockDictationPolicy()

        XCTAssertEqual(
            policy.handle(.keyDown, isRecording: true),
            .stop
        )
        XCTAssertEqual(
            policy.handle(.keyUp, isRecording: false),
            .none
        )
        XCTAssertEqual(
            policy.handle(.keyDown, isRecording: false),
            .start
        )
    }

    func testReleaseWithoutMatchingPressIsIgnored() {
        var policy = CapsLockDictationPolicy()

        XCTAssertEqual(
            policy.handle(.keyUp, isRecording: true),
            .none
        )
        XCTAssertFalse(policy.isPressActive)
    }
}
