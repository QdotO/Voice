import XCTest

@testable import WhisperShared

final class LegacyAppPreferencesSettingsStoreTests: XCTestCase {
    func testEnglishBaseModelMapsToBalancedProfile() {
        let selection = LegacyAppPreferencesSettingsStore.resolveLegacyModel("base.en")

        XCTAssertEqual(selection.profile, .balanced)
        XCTAssertNil(selection.rawModelOverride)
    }

    func testMultilingualBaseMapsToMultilingualProfile() {
        let selection = LegacyAppPreferencesSettingsStore.resolveLegacyModel("base")

        XCTAssertEqual(selection.profile, .multilingual)
        XCTAssertNil(selection.rawModelOverride)
    }

    func testUnknownLegacyModelBecomesRawOverride() {
        let selection = LegacyAppPreferencesSettingsStore.resolveLegacyModel("large-v3")

        XCTAssertEqual(selection.profile, .balanced)
        XCTAssertEqual(selection.rawModelOverride, "large-v3")
    }

    func testStoreLoadsRecordingModeAndClipboardPreference() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("small.en", forKey: "selectedModel")
        defaults.set(false, forKey: "alwaysCopyToClipboard")
        defaults.set("toggle", forKey: "recordingMode")

        let store = LegacyAppPreferencesSettingsStore(userDefaults: defaults)
        let settings = store.load()

        XCTAssertEqual(settings.selectedProfile, .accurate)
        XCTAssertTrue(settings.preserveClipboard)
        XCTAssertEqual(settings.recordingMode, .toggle)
    }
}
