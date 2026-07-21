import Foundation

public enum ModelProfile: String, CaseIterable, Codable, Sendable {
    case fast
    case balanced
    case accurate
    case multilingual

    public static let defaultProfile: ModelProfile = .balanced

    public var displayName: String {
        switch self {
        case .fast:
            return "Fast"
        case .balanced:
            return "Balanced"
        case .accurate:
            return "Accurate"
        case .multilingual:
            return "Multilingual"
        }
    }

    public var detailText: String {
        switch self {
        case .fast:
            return "Fastest startup and lowest latency. Best for quick notes and short commands."
        case .balanced:
            return "Default profile. Best speed-to-accuracy tradeoff for everyday English dictation."
        case .accurate:
            return "Higher accuracy for technical and domain-heavy dictation at a higher compute cost."
        case .multilingual:
            return "Use when you need multilingual recognition instead of English-only speed."
        }
    }

    public var defaultModelName: String {
        switch self {
        case .fast:
            return "tiny.en"
        case .balanced:
            return "base.en"
        case .accurate:
            return "small.en"
        case .multilingual:
            return "base"
        }
    }

    public func resolvedModelName(rawOverride: String? = nil) -> String {
        let trimmed = rawOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return defaultModelName
    }
}

public enum RecordingModePreference: String, CaseIterable, Codable, Sendable {
    case hold
    case toggle
}

public enum DictationStopPolicy {
    public static func allowsAutomaticStop(
        recordingMode: RecordingModePreference,
        isEnabled: Bool
    ) -> Bool {
        // Both interaction modes support silence completion. Toggle controls how
        // recording starts and how an explicit stop works, not whether silence
        // detection is available.
        _ = recordingMode
        return isEnabled
    }

    public static func shouldStopAfterSilence(
        now: TimeInterval,
        lastVoiceActivity: TimeInterval,
        lastPartialUpdate: TimeInterval,
        hasPartialTranscript: Bool,
        silenceWindow: TimeInterval,
        trailingPartialGrace: TimeInterval
    ) -> Bool {
        let silenceSettled = now - lastVoiceActivity >= silenceWindow
        let partialSettled =
            !hasPartialTranscript || now - lastPartialUpdate >= trailingPartialGrace
        return silenceSettled && partialSettled
    }
}

public struct WhisperSettings: Codable, Equatable, Sendable {
    public static let defaults = WhisperSettings()

    public var selectedProfile: ModelProfile
    public var rawModelOverride: String?
    public var prewarmEnabled: Bool
    public var livePartialsEnabled: Bool
    public var preserveClipboard: Bool
    public var recordingMode: RecordingModePreference

    public init(
        selectedProfile: ModelProfile = .defaultProfile,
        rawModelOverride: String? = nil,
        prewarmEnabled: Bool = true,
        livePartialsEnabled: Bool = true,
        preserveClipboard: Bool = true,
        recordingMode: RecordingModePreference = .toggle
    ) {
        self.selectedProfile = selectedProfile
        self.rawModelOverride = Self.normalize(rawModelOverride)
        self.prewarmEnabled = prewarmEnabled
        self.livePartialsEnabled = livePartialsEnabled
        self.preserveClipboard = preserveClipboard
        self.recordingMode = recordingMode
    }

    public var resolvedModelName: String {
        selectedProfile.resolvedModelName(rawOverride: rawModelOverride)
    }

    private static func normalize(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }
}

public protocol SettingsStore {
    func load() -> WhisperSettings
    func save(_ settings: WhisperSettings)
}

public final class UserDefaultsSettingsStore: SettingsStore {
    private enum Key {
        static let selectedProfile = "v2.selectedProfile"
        static let rawModelOverride = "v2.rawModelOverride"
        static let prewarmEnabled = "v2.prewarmEnabled"
        static let livePartialsEnabled = "v2.livePartialsEnabled"
        static let preserveClipboard = "v2.preserveClipboard"
        static let recordingMode = "v2.recordingMode"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> WhisperSettings {
        let defaults = WhisperSettings.defaults
        let profile = ModelProfile(rawValue: userDefaults.string(forKey: Key.selectedProfile) ?? "")
            ?? defaults.selectedProfile
        let recordingMode = RecordingModePreference(
            rawValue: userDefaults.string(forKey: Key.recordingMode) ?? "")
            ?? defaults.recordingMode

        return WhisperSettings(
            selectedProfile: profile,
            rawModelOverride: userDefaults.string(forKey: Key.rawModelOverride),
            prewarmEnabled: userDefaults.object(forKey: Key.prewarmEnabled) as? Bool
                ?? defaults.prewarmEnabled,
            livePartialsEnabled: userDefaults.object(forKey: Key.livePartialsEnabled) as? Bool
                ?? defaults.livePartialsEnabled,
            preserveClipboard: userDefaults.object(forKey: Key.preserveClipboard) as? Bool
                ?? defaults.preserveClipboard,
            recordingMode: recordingMode
        )
    }

    public func save(_ settings: WhisperSettings) {
        userDefaults.set(settings.selectedProfile.rawValue, forKey: Key.selectedProfile)
        if let override = settings.rawModelOverride {
            userDefaults.set(override, forKey: Key.rawModelOverride)
        } else {
            userDefaults.removeObject(forKey: Key.rawModelOverride)
        }
        userDefaults.set(settings.prewarmEnabled, forKey: Key.prewarmEnabled)
        userDefaults.set(settings.livePartialsEnabled, forKey: Key.livePartialsEnabled)
        userDefaults.set(settings.preserveClipboard, forKey: Key.preserveClipboard)
        userDefaults.set(settings.recordingMode.rawValue, forKey: Key.recordingMode)
    }
}

public final class InMemorySettingsStore: SettingsStore {
    private var settings: WhisperSettings

    public init(settings: WhisperSettings = .defaults) {
        self.settings = settings
    }

    public func load() -> WhisperSettings {
        settings
    }

    public func save(_ settings: WhisperSettings) {
        self.settings = settings
    }
}
