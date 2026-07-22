import Foundation

public enum CapsLockDictationInput: Equatable, Sendable {
    case keyDown
    case keyUp
    case flagsChanged(isOn: Bool)
}

public enum CapsLockDictationAction: Equatable, Sendable {
    case none
    case start
    case stop
}

/// Keeps Caps Lock's keyDown/keyUp and flagsChanged events as one press.
/// A press starts idle dictation and stops active dictation. Release only stops
/// dictation when that same press started it.
public struct CapsLockDictationPolicy: Sendable {
    private enum PressIntent: Equatable, Sendable {
        case startedDictation
        case stoppedDictation
    }

    private var pressIntent: PressIntent?

    public private(set) var isPressActive = false

    public init() {}

    public mutating func handle(
        _ input: CapsLockDictationInput,
        isRecording: Bool
    ) -> CapsLockDictationAction {
        switch input {
        case .keyDown:
            return beginPress(isRecording: isRecording)
        case .keyUp:
            return endPress()
        case .flagsChanged(let isOn):
            return isOn ? beginPress(isRecording: isRecording) : endPress()
        }
    }

    public mutating func reset() {
        pressIntent = nil
        isPressActive = false
    }

    private mutating func beginPress(isRecording: Bool) -> CapsLockDictationAction {
        guard !isPressActive else { return .none }

        isPressActive = true
        if isRecording {
            pressIntent = .stoppedDictation
            return .stop
        }

        pressIntent = .startedDictation
        return .start
    }

    private mutating func endPress() -> CapsLockDictationAction {
        guard isPressActive else { return .none }

        isPressActive = false
        defer { pressIntent = nil }
        return pressIntent == .startedDictation ? .stop : .none
    }
}

public enum CapsLockEventTapInstallTrigger: String, Equatable, Sendable {
    case launch
    case appActivation
    case accessibilityRequestCompletion
    case settingsEnabled
}

/// Tracks event-tap ownership without scheduling retries. Failed attempts stay
/// uninstalled; caller decides when a meaningful lifecycle trigger permits retry.
public struct CapsLockEventTapInstallationState: Equatable, Sendable {
    public private(set) var isInstalled = false

    public init() {}

    public func shouldAttempt(isEnabled: Bool) -> Bool {
        isEnabled && !isInstalled
    }

    public mutating func markInstalled() {
        isInstalled = true
    }

    public mutating func reset() {
        isInstalled = false
    }
}

public enum CapsLockActionDispatchPath: String, Equatable, Sendable {
    case immediate
    case mainQueue
}

/// Keeps callback dispatch testable while preserving a main-queue fallback for
/// callbacks that arrive off the main thread.
public enum CapsLockActionDispatcher {
    public static func path(isMainThread: Bool) -> CapsLockActionDispatchPath {
        isMainThread ? .immediate : .mainQueue
    }

    public static func dispatch(
        isMainThread: Bool,
        action: @escaping () -> Void,
        enqueue: (@escaping () -> Void) -> Void
    ) {
        if isMainThread {
            action()
        } else {
            enqueue(action)
        }
    }
}

public extension Notification.Name {
    static let whisperAccessibilityRequestCompleted = Notification.Name(
        "WhisperAccessibilityRequestCompleted"
    )
}
