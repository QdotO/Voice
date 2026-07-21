import Foundation

public final class LegacyAppPreferencesSettingsStore: SettingsStore {
    private enum Key {
        static let selectedModel = "selectedModel"
        static let alwaysCopyToClipboard = "alwaysCopyToClipboard"
        static let recordingMode = "recordingMode"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> WhisperSettings {
        let legacyModel = userDefaults.string(forKey: Key.selectedModel)
        let modelSelection = Self.resolveLegacyModel(legacyModel)
        let preserveClipboard = !(userDefaults.object(forKey: Key.alwaysCopyToClipboard) as? Bool ?? true)
        let recordingMode = RecordingModePreference(
            rawValue: userDefaults.string(forKey: Key.recordingMode) ?? ""
        ) ?? .hold

        return WhisperSettings(
            selectedProfile: modelSelection.profile,
            rawModelOverride: modelSelection.rawModelOverride,
            preserveClipboard: preserveClipboard,
            recordingMode: recordingMode
        )
    }

    public func save(_ settings: WhisperSettings) {
        userDefaults.set(settings.resolvedModelName, forKey: Key.selectedModel)
        userDefaults.set(!settings.preserveClipboard, forKey: Key.alwaysCopyToClipboard)
        userDefaults.set(settings.recordingMode.rawValue, forKey: Key.recordingMode)
    }

    public static func resolveLegacyModel(_ rawModel: String?) -> (
        profile: ModelProfile, rawModelOverride: String?
    ) {
        let normalized = rawModel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case nil, "":
            return (.balanced, nil)
        case "tiny.en":
            return (.fast, nil)
        case "base.en":
            return (.balanced, nil)
        case "small.en":
            return (.accurate, nil)
        case "base":
            return (.multilingual, nil)
        case "tiny":
            return (.fast, "tiny")
        case "small":
            return (.accurate, "small")
        default:
            return (.balanced, normalized)
        }
    }
}
