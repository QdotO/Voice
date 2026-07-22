import XCTest

@testable import WhisperShared

final class PermissionStateTests: XCTestCase {
    func testInitialStateHasNoSnapshotAndNoRefreshTrigger() {
        XCTAssertEqual(PermissionState.initial.snapshot, .initial)
        XCTAssertNil(PermissionState.initial.lastRefresh)
    }

    func testAppearRefreshReplacesInitialSnapshot() {
        let fresh = PermissionSnapshot(microphone: .granted, accessibility: .denied)

        let state = PermissionStateReducer.reduce(
            .initial,
            event: .refresh(trigger: .appear, snapshot: fresh)
        )

        XCTAssertEqual(state.snapshot, fresh)
        XCTAssertEqual(state.lastRefresh, .appear)
    }

    func testActivationRefreshReadsNewSystemState() {
        let state = PermissionState(snapshot: PermissionSnapshot(microphone: .denied, accessibility: .denied))
        let fresh = PermissionSnapshot(microphone: .granted, accessibility: .granted)

        let refreshed = PermissionStateReducer.reduce(
            state,
            event: .refresh(trigger: .activation, snapshot: fresh)
        )

        XCTAssertEqual(refreshed.snapshot, fresh)
        XCTAssertEqual(refreshed.lastRefresh, .activation)
    }

    func testAsyncMicrophoneRequestCompletionRefreshesMicrophoneState() {
        let state = PermissionState(
            snapshot: PermissionSnapshot(microphone: .unknown, accessibility: .granted)
        )
        let completed = PermissionSnapshot(microphone: .granted, accessibility: .granted)

        let refreshed = PermissionStateReducer.reduce(
            state,
            event: .refresh(trigger: .microphoneRequestCompletion, snapshot: completed)
        )

        XCTAssertEqual(refreshed.snapshot.microphone, .granted)
        XCTAssertEqual(refreshed.snapshot.accessibility, .granted)
        XCTAssertEqual(refreshed.lastRefresh, .microphoneRequestCompletion)
    }

    func testAccessibilityChangeRefreshesOnlyChangedSnapshotValue() {
        let state = PermissionState(
            snapshot: PermissionSnapshot(microphone: .granted, accessibility: .denied)
        )
        let changed = PermissionSnapshot(microphone: .granted, accessibility: .granted)

        let refreshed = PermissionStateReducer.reduce(
            state,
            event: .refresh(trigger: .accessibilityChanged, snapshot: changed)
        )

        XCTAssertEqual(refreshed.snapshot.microphone, .granted)
        XCTAssertEqual(refreshed.snapshot.accessibility, .granted)
        XCTAssertEqual(refreshed.lastRefresh, .accessibilityChanged)
    }

    func testStaleDeniedSnapshotBecomesFreshAfterRequestCompletion() {
        let stale = PermissionState(
            snapshot: PermissionSnapshot(microphone: .denied, accessibility: .denied),
            lastRefresh: .appear
        )
        let fresh = PermissionSnapshot(microphone: .granted, accessibility: .denied)

        let refreshed = PermissionStateReducer.reduce(
            stale,
            event: .refresh(trigger: .microphoneRequestCompletion, snapshot: fresh)
        )

        XCTAssertEqual(refreshed.snapshot, fresh)
        XCTAssertEqual(refreshed.lastRefresh, .microphoneRequestCompletion)
    }

    func testPermissionQueryUsesInjectedReaders() {
        let query = PermissionSnapshotQuery(
            microphone: { .granted },
            accessibility: { .denied }
        )

        XCTAssertEqual(
            query.snapshot(),
            PermissionSnapshot(microphone: .granted, accessibility: .denied)
        )
    }
}
