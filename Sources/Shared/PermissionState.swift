import Foundation

public enum PermissionAccessState: Equatable, Sendable {
    case unknown
    case granted
    case denied

    public var isGranted: Bool {
        self == .granted
    }
}

public struct PermissionSnapshot: Equatable, Sendable {
    public var microphone: PermissionAccessState
    public var accessibility: PermissionAccessState

    public init(
        microphone: PermissionAccessState,
        accessibility: PermissionAccessState
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
    }

    public static let initial = PermissionSnapshot(
        microphone: .unknown,
        accessibility: .unknown
    )
}

public enum PermissionRefreshTrigger: Equatable, Sendable {
    case appear
    case activation
    case microphoneRequestCompletion
    case accessibilityRequestCompletion
    case accessibilityChanged
}

public struct PermissionState: Equatable, Sendable {
    public var snapshot: PermissionSnapshot
    public var lastRefresh: PermissionRefreshTrigger?

    public init(
        snapshot: PermissionSnapshot = .initial,
        lastRefresh: PermissionRefreshTrigger? = nil
    ) {
        self.snapshot = snapshot
        self.lastRefresh = lastRefresh
    }

    public static let initial = PermissionState()
}

public enum PermissionStateEvent: Equatable, Sendable {
    case refresh(trigger: PermissionRefreshTrigger, snapshot: PermissionSnapshot)
}

public enum PermissionStateReducer {
    public static func reduce(
        _ state: PermissionState,
        event: PermissionStateEvent
    ) -> PermissionState {
        switch event {
        case let .refresh(trigger, snapshot):
            return PermissionState(snapshot: snapshot, lastRefresh: trigger)
        }
    }
}

/// Reads current permission state without coupling the reducer or tests to system APIs.
public struct PermissionSnapshotQuery {
    private let microphoneReader: () -> PermissionAccessState
    private let accessibilityReader: () -> PermissionAccessState

    public init(
        microphone: @escaping () -> PermissionAccessState,
        accessibility: @escaping () -> PermissionAccessState
    ) {
        microphoneReader = microphone
        accessibilityReader = accessibility
    }

    public func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphoneReader(),
            accessibility: accessibilityReader()
        )
    }
}
