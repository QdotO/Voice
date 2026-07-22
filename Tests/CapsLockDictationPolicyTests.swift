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

    func testActionDispatcherRunsImmediatelyOnMainPath() {
        var calls = 0
        var enqueued = false

        CapsLockActionDispatcher.dispatch(
            isMainThread: true,
            action: { calls += 1 },
            enqueue: { _ in enqueued = true }
        )

        XCTAssertEqual(calls, 1)
        XCTAssertFalse(enqueued)
        XCTAssertEqual(
            CapsLockActionDispatcher.path(isMainThread: true),
            .immediate
        )
    }

    func testActionDispatcherUsesFallbackWhenOffMain() {
        var calls = 0
        var queuedAction: (() -> Void)?

        CapsLockActionDispatcher.dispatch(
            isMainThread: false,
            action: { calls += 1 },
            enqueue: { queuedAction = $0 }
        )

        XCTAssertEqual(calls, 0)
        XCTAssertEqual(
            CapsLockActionDispatcher.path(isMainThread: false),
            .mainQueue
        )
        queuedAction?()
        XCTAssertEqual(calls, 1)
    }

    func testEventTapInstallationStateAllowsRetryAfterFailureButNotAfterInstall() {
        var state = CapsLockEventTapInstallationState()

        XCTAssertTrue(state.shouldAttempt(isEnabled: true))
        XCTAssertTrue(state.shouldAttempt(isEnabled: true))

        state.markInstalled()
        XCTAssertFalse(state.shouldAttempt(isEnabled: true))
        XCTAssertFalse(state.shouldAttempt(isEnabled: false))

        state.reset()
        XCTAssertTrue(state.shouldAttempt(isEnabled: true))
    }
}
