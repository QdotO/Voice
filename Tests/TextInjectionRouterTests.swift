import XCTest

@testable import WhisperShared

final class TextInjectionRouterTests: XCTestCase {

    // MARK: - AX Insert Detection

    func testVSCodeBundleIDForcesAXInsert() {
        let ids = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.microsoft.VSCodeInsiders2",
            "com.vscodium",
        ]
        for id in ids {
            XCTAssertTrue(
                TextInjectionRouter.shouldForceAXInsert(bundleID: id, appName: ""),
                "Expected AX insert for bundle ID: \(id)"
            )
        }
    }

    func testVSCodeAppNameForcesAXInsert() {
        XCTAssertTrue(
            TextInjectionRouter.shouldForceAXInsert(
                bundleID: nil, appName: "Visual Studio Code - Insiders"
            )
        )
        XCTAssertTrue(
            TextInjectionRouter.shouldForceAXInsert(
                bundleID: nil, appName: "VS Code Insiders"
            )
        )
    }

    func testUnknownAppDoesNotForceAXInsert() {
        XCTAssertFalse(
            TextInjectionRouter.shouldForceAXInsert(
                bundleID: "com.apple.TextEdit", appName: "TextEdit"
            )
        )
        XCTAssertFalse(
            TextInjectionRouter.shouldForceAXInsert(
                bundleID: nil, appName: "Safari"
            )
        )
    }

    func testNilBundleIDDoesNotCrash() {
        XCTAssertFalse(
            TextInjectionRouter.shouldForceAXInsert(bundleID: nil, appName: "Notes")
        )
        XCTAssertFalse(
            TextInjectionRouter.shouldForcePaste(bundleID: nil, appName: "Notes")
        )
    }

    // MARK: - Paste Detection

    func testVSCodeBundleIDForcesPaste() {
        let ids = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
        ]
        for id in ids {
            XCTAssertTrue(
                TextInjectionRouter.shouldForcePaste(bundleID: id, appName: ""),
                "Expected paste for bundle ID: \(id)"
            )
        }
    }

    func testUnknownAppDoesNotForcePaste() {
        XCTAssertFalse(
            TextInjectionRouter.shouldForcePaste(
                bundleID: "com.apple.Notes", appName: "Notes"
            )
        )
    }

    // MARK: - Strategy Routing

    func testVSCodeGetsAXInsertStrategy() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.microsoft.VSCode",
            appName: "Visual Studio Code",
            userPrefersPaste: false
        )
        XCTAssertEqual(strategy, .axInsert)
    }

    func testAXInsertTakesPriorityOverPaste() {
        // VS Code matches both AX insert AND paste patterns.
        // AX insert should win.
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.microsoft.VSCode",
            appName: "Visual Studio Code",
            userPrefersPaste: true
        )
        XCTAssertEqual(strategy, .axInsert)
    }

    func testUserPrefersPasteForRegularApp() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.apple.Notes",
            appName: "Notes",
            userPrefersPaste: true
        )
        XCTAssertEqual(strategy, .paste)
    }

    func testDefaultStrategyIsType() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.apple.TextEdit",
            appName: "TextEdit",
            userPrefersPaste: false
        )
        XCTAssertEqual(strategy, .type)
    }

    func testNilBundleIDWithPastePreference() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: nil,
            appName: "SomeApp",
            userPrefersPaste: true
        )
        XCTAssertEqual(strategy, .paste)
    }

    func testNilBundleIDDefaultsToType() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: nil,
            appName: "SomeApp",
            userPrefersPaste: false
        )
        XCTAssertEqual(strategy, .type)
    }

    // MARK: - Case Insensitive Name Matching

    func testNameMatchingIsCaseInsensitive() {
        XCTAssertTrue(
            TextInjectionRouter.shouldForceAXInsert(
                bundleID: nil, appName: "visual studio code - insiders"
            )
        )
        XCTAssertTrue(
            TextInjectionRouter.shouldForceAXInsert(
                bundleID: nil, appName: "VISUAL STUDIO CODE - INSIDERS"
            )
        )
    }

    // MARK: - Regression Guards

    func testBundleIDSetsAreNotEmpty() {
        // Guard against accidentally clearing the bundle ID sets
        XCTAssertFalse(TextInjectionRouter.axInsertBundleIDs.isEmpty)
        XCTAssertFalse(TextInjectionRouter.pasteBundleIDs.isEmpty)
    }

    func testAllAXInsertBundleIDsAlsoForcePaste() {
        // Currently both sets are identical. This test ensures consistency:
        // any app that gets AX insert should also be in the paste set as a fallback.
        for id in TextInjectionRouter.axInsertBundleIDs {
            XCTAssertTrue(
                TextInjectionRouter.pasteBundleIDs.contains(id),
                "AX insert bundle ID '\(id)' is missing from paste bundle IDs"
            )
        }
    }

    func testEmptyAppNameDoesNotMatch() {
        XCTAssertFalse(
            TextInjectionRouter.shouldForceAXInsert(bundleID: nil, appName: "")
        )
        XCTAssertFalse(
            TextInjectionRouter.shouldForcePaste(bundleID: nil, appName: "")
        )
    }
}
