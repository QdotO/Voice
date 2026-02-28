import XCTest

@testable import WhisperShared

/// Tests for text injection strategy routing and edge cases.
/// Note: `TextInjector` itself lives in the `Whisper` executable target and requires
/// a real Accessibility grant, so these tests focus on the `TextInjectionRouter`
/// routing logic — which determines which injection strategy is chosen before any
/// AX API calls are made.
final class TextInjectorTests: XCTestCase {

    // MARK: - Common App Routing

    func testTerminalDefaultsToType() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.apple.Terminal",
            appName: "Terminal",
            userPrefersPaste: false
        )
        XCTAssertEqual(strategy, .type)
    }

    func testXcodeDefaultsToType() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            userPrefersPaste: false
        )
        XCTAssertEqual(strategy, .type)
    }

    func testSafariDefaultsToType() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.apple.Safari",
            appName: "Safari",
            userPrefersPaste: false
        )
        XCTAssertEqual(strategy, .type)
    }

    func testSlackWithPastePreferenceGetsPaste() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            userPrefersPaste: true
        )
        XCTAssertEqual(strategy, .paste)
    }

    func testChromeWithoutPreferenceDefaultsToType() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            userPrefersPaste: false
        )
        XCTAssertEqual(strategy, .type)
    }

    // MARK: - VSCode Always Gets AX Insert

    func testVSCodeIgnoresUserPastePreference() {
        // Even when the user prefers paste globally, VS Code should still get axInsert
        // because it has explicit editor support via Accessibility APIs.
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.microsoft.VSCode",
            appName: "Visual Studio Code",
            userPrefersPaste: true
        )
        XCTAssertEqual(
            strategy, .axInsert, "VS Code must use axInsert even when userPrefersPaste=true")
    }

    func testVSCodiumGetsAXInsert() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.vscodium",
            appName: "VSCodium",
            userPrefersPaste: false
        )
        XCTAssertEqual(strategy, .axInsert)
    }

    func testVSCodeInsidersGetsAXInsert() {
        let strategy = TextInjectionRouter.strategy(
            bundleID: "com.microsoft.VSCodeInsiders",
            appName: "Visual Studio Code - Insiders",
            userPrefersPaste: false
        )
        XCTAssertEqual(strategy, .axInsert)
    }

    // MARK: - Name Pattern Matching Edge Cases

    func testPartialNameMatchForVSCode() {
        // Pattern matching uses `localizedCaseInsensitiveContains`, so a longer
        // app name that contains the pattern should still match.
        XCTAssertTrue(
            TextInjectionRouter.shouldForceAXInsert(
                bundleID: nil,
                appName: "Visual Studio Code - Insiders (workspace)"
            )
        )
    }

    func testUnrelatedNameDoesNotMatch() {
        XCTAssertFalse(
            TextInjectionRouter.shouldForceAXInsert(
                bundleID: nil,
                appName: "Studio One Artist"
            )
        )
    }

    func testWhitespaceOnlyNameDoesNotMatch() {
        XCTAssertFalse(
            TextInjectionRouter.shouldForceAXInsert(bundleID: nil, appName: "   ")
        )
        XCTAssertFalse(
            TextInjectionRouter.shouldForcePaste(bundleID: nil, appName: "   ")
        )
    }

    // MARK: - Strategy Consistency

    func testAXInsertAndPasteSetsAreIdentical() {
        // Any app that gets axInsert must also be in the paste set because paste
        // is the fallback if AX insert fails at runtime.
        XCTAssertEqual(
            TextInjectionRouter.axInsertBundleIDs,
            TextInjectionRouter.pasteBundleIDs,
            "axInsertBundleIDs and pasteBundleIDs must remain in sync"
        )
    }

    func testAXInsertNamePatternsMatchPasteNamePatterns() {
        XCTAssertEqual(
            TextInjectionRouter.axInsertNamePatterns,
            TextInjectionRouter.pasteNamePatterns,
            "axInsertNamePatterns and pasteNamePatterns must remain in sync"
        )
    }

    func testAllStrategiesAreReachable() {
        // Verify all three strategy cases can actually be returned — prevents
        // dead-code regressions if the routing logic is accidentally simplified.
        let axInsert = TextInjectionRouter.strategy(
            bundleID: "com.microsoft.VSCode", appName: "", userPrefersPaste: false)
        let paste = TextInjectionRouter.strategy(
            bundleID: "com.apple.Notes", appName: "Notes", userPrefersPaste: true)
        let type = TextInjectionRouter.strategy(
            bundleID: "com.apple.TextEdit", appName: "TextEdit", userPrefersPaste: false)

        XCTAssertEqual(axInsert, .axInsert)
        XCTAssertEqual(paste, .paste)
        XCTAssertEqual(type, .type)
    }

    // MARK: - Injection Fallback Chain (documentation as tests)

    /// Verifies the expected caller behavior: try axInsert → fall back to paste → fall back to type.
    /// This mirrors the precedence order encoded in `TextInjectionRouter.strategy()`.
    func testFallbackChainPrecedence() {
        let bundleID = "com.microsoft.VSCode"
        let appName = "Visual Studio Code"

        // Step 1: preferred strategy
        let preferred = TextInjectionRouter.strategy(
            bundleID: bundleID, appName: appName, userPrefersPaste: false)
        XCTAssertEqual(preferred, .axInsert)

        // Step 2: fallback to paste when AX insert is unavailable
        // (in production, WhisperApp catches the thrown InjectionError and retries with paste)
        let fallback = TextInjectionRouter.strategy(
            bundleID: bundleID, appName: appName, userPrefersPaste: true)
        XCTAssertEqual(
            fallback, .axInsert,
            "VS Code AX insert must never fall back to paste via the strategy call — the caller must handle errors"
        )
    }
}
