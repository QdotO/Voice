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
