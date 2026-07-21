import XCTest

@testable import WhisperShared

final class InsertionAppProfileCatalogTests: XCTestCase {
    func testVSCodeResolvesToAXInsertProfile() {
        let profile = InsertionAppProfileCatalog.resolve(
            bundleIdentifier: "com.microsoft.VSCode",
            applicationName: "Visual Studio Code"
        )

        XCTAssertEqual(profile.preferredStrategy, .axInsert)
        XCTAssertEqual(profile.fallbackStrategies, [.paste, .type])
        XCTAssertEqual(profile.version, InsertionAppProfileCatalog.version)
    }

    func testBrowserResolvesToPasteProfile() {
        let profile = InsertionAppProfileCatalog.resolve(
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari"
        )

        XCTAssertEqual(profile.preferredStrategy, .paste)
        XCTAssertEqual(profile.fallbackStrategies, [.type])
    }

    func testTerminalPrefersPasteWhenUserRequestsIt() {
        let profile = InsertionAppProfileCatalog.resolve(
            bundleIdentifier: "com.apple.Terminal",
            applicationName: "Terminal",
            userPrefersPaste: true
        )

        XCTAssertEqual(profile.preferredStrategy, .paste)
        XCTAssertEqual(profile.fallbackStrategies, [.type, .paste])
    }
}
