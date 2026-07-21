import XCTest

@testable import WhisperShared

final class V2SettingsTests: XCTestCase {
    func testModelProfilesResolveExpectedModelNames() {
        XCTAssertEqual(ModelProfile.fast.resolvedModelName(), "tiny.en")
        XCTAssertEqual(ModelProfile.balanced.resolvedModelName(), "base.en")
        XCTAssertEqual(ModelProfile.accurate.resolvedModelName(), "small.en")
        XCTAssertEqual(ModelProfile.multilingual.resolvedModelName(), "base")
    }

    func testRawModelOverrideTakesPriorityWhenPresent() {
        XCTAssertEqual(
            ModelProfile.balanced.resolvedModelName(rawOverride: " custom-model "),
            "custom-model"
        )
    }

    func testUserDefaultsSettingsStoreRoundTripsTypedSettings() {
        let suiteName = "WhisperV2SettingsTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected suite-specific user defaults")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        let settings = WhisperSettings(
            selectedProfile: .accurate,
            rawModelOverride: "small-custom",
            prewarmEnabled: false,
            livePartialsEnabled: true,
            preserveClipboard: false,
            recordingMode: .toggle
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testSettingsNormalizeBlankOverridesToNil() {
        let settings = WhisperSettings(rawModelOverride: "   ")
        XCTAssertNil(settings.rawModelOverride)
        XCTAssertEqual(settings.resolvedModelName, "base.en")
    }

    func testDefaultsUseToggleRecordingMode() {
        XCTAssertEqual(WhisperSettings.defaults.recordingMode, .toggle)
    }

    func testAutomaticStopFollowsEnabledPreferenceInBothModes() {
        XCTAssertTrue(
            DictationStopPolicy.allowsAutomaticStop(recordingMode: .toggle, isEnabled: true)
        )
        XCTAssertFalse(
            DictationStopPolicy.allowsAutomaticStop(recordingMode: .toggle, isEnabled: false)
        )
        XCTAssertTrue(
            DictationStopPolicy.allowsAutomaticStop(recordingMode: .hold, isEnabled: true)
        )
        XCTAssertFalse(
            DictationStopPolicy.allowsAutomaticStop(recordingMode: .hold, isEnabled: false)
        )
    }

    func testRecentVoicePreventsStopEvenWhenPartialIsStale() {
        XCTAssertFalse(
            DictationStopPolicy.shouldStopAfterSilence(
                now: 20,
                lastVoiceActivity: 19.5,
                lastPartialUpdate: 10,
                hasPartialTranscript: true,
                silenceWindow: 1.5,
                trailingPartialGrace: 0.42
            )
        )
    }

    func testSettledSilenceStopsAfterPartialGrace() {
        XCTAssertTrue(
            DictationStopPolicy.shouldStopAfterSilence(
                now: 20,
                lastVoiceActivity: 18,
                lastPartialUpdate: 19,
                hasPartialTranscript: true,
                silenceWindow: 1.5,
                trailingPartialGrace: 0.42
            )
        )
    }

    func testFreshPartialDelaysSilenceStop() {
        XCTAssertFalse(
            DictationStopPolicy.shouldStopAfterSilence(
                now: 20,
                lastVoiceActivity: 18,
                lastPartialUpdate: 19.8,
                hasPartialTranscript: true,
                silenceWindow: 1.5,
                trailingPartialGrace: 0.42
            )
        )
    }
}
