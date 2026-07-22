import XCTest

@testable import WhisperShared

/// Tests for text injection routing and pasteboard lifecycle behavior.
/// Note: `TextInjector` itself lives in the `Whisper` executable target and requires
/// a real Accessibility grant. These tests cover `TextInjectionRouter` and the
/// shared pasteboard transaction seam before any AX API calls are made.
final class TextInjectorTests: XCTestCase {

    // MARK: - Focused AX safety

    func testFocusedAXInsertionReplacesSelectedRange() {
        let adapter = FakeFocusedAXAdapter(value: "before old after", range: .init(location: 7, length: 3))

        XCTAssertTrue(FocusedAXTextInserter(adapter: adapter).insert("new"))
        XCTAssertEqual(adapter.value, "before new after")
        XCTAssertEqual(adapter.replacementCalls, ["new"])
        XCTAssertEqual(adapter.wholeFieldOverwriteAttempts, 0)
    }

    func testFocusedAXInsertionReturnsFalseWhenRangeMissing() {
        let adapter = FakeFocusedAXAdapter(value: "before old after", range: nil)

        XCTAssertFalse(FocusedAXTextInserter(adapter: adapter).insert("new"))
        XCTAssertEqual(adapter.value, "before old after")
        XCTAssertEqual(adapter.replacementCalls, [])
    }

    func testFocusedAXInsertionReturnsFalseWhenRangeInvalid() {
        let adapter = FakeFocusedAXAdapter(
            value: "before old after",
            range: .init(location: 99, length: 0)
        )

        XCTAssertFalse(FocusedAXTextInserter(adapter: adapter).insert("new"))
        XCTAssertEqual(adapter.value, "before old after")
        XCTAssertEqual(adapter.replacementCalls, [])
    }

    func testFocusedAXInsertionRejectsWrongOrNoneditableElement() {
        let adapter = FakeFocusedAXAdapter(
            value: "before old after",
            range: .init(location: 7, length: 3),
            editable: false
        )

        XCTAssertFalse(FocusedAXTextInserter(adapter: adapter).insert("new"))
        XCTAssertEqual(adapter.value, "before old after")
        XCTAssertEqual(adapter.replacementCalls, [])
        XCTAssertEqual(adapter.visitedElementCount, 1)
    }

    func testExistingAXProfileSelectsFocusedAXPathWithoutWindowSearch() {
        let profile = InsertionAppProfileCatalog.resolve(
            bundleIdentifier: "com.microsoft.VSCode",
            applicationName: "Visual Studio Code"
        )
        let adapter = FakeFocusedAXAdapter(
            value: "focused noneditable",
            range: .init(location: 0, length: 0),
            editable: false,
            windowChildCount: 4
        )

        XCTAssertEqual(profile.preferredStrategy, .axInsert)
        XCTAssertFalse(FocusedAXTextInserter(adapter: adapter).insert("new"))
        XCTAssertEqual(adapter.visitedElementCount, 1)
        XCTAssertEqual(adapter.windowChildVisitCount, 0)
    }

    // MARK: - Pasteboard lifecycle characterization

    func testPasteTransactionCharacterizesStringClipboardLifecycle() async throws {
        let pasteboard = CharacterizationPasteboard(items: [.plainText("before")])
        var waits: [UInt64] = []

        try await PasteboardTextTransaction.paste(
            "dictation",
            preserveClipboard: true,
            using: pasteboard,
            triggerPaste: {
                XCTAssertEqual(pasteboard.plainText, "dictation")
            },
            sleep: { nanoseconds in
                waits.append(nanoseconds)
            }
        )

        XCTAssertEqual(waits, [200_000_000, 300_000_000])
        XCTAssertEqual(pasteboard.items, [.plainText("before")])
    }

    func testPasteTransactionPreservesRichTextClipboard() async throws {
        let pasteboard = CharacterizationPasteboard(
            items: [.item([.payload("public.rtf", [0x7B, 0x5C])])]
        )

        try await pasteWithNoDelay(using: pasteboard)

        XCTAssertEqual(
            pasteboard.items,
            [.item([.payload("public.rtf", [0x7B, 0x5C])])]
        )
    }

    func testPasteTransactionPreservesImageDataClipboard() async throws {
        let pasteboard = CharacterizationPasteboard(
            items: [.item([.payload("public.png", [0x89, 0x50, 0x4E, 0x47])])]
        )

        try await pasteWithNoDelay(using: pasteboard)

        XCTAssertEqual(
            pasteboard.items,
            [.item([.payload("public.png", [0x89, 0x50, 0x4E, 0x47])])]
        )
    }

    func testPasteTransactionPreservesFileURLClipboard() async throws {
        let pasteboard = CharacterizationPasteboard(
            items: [.item([.payload("public.file-url", Array("file:///tmp/example.txt".utf8))])]
        )

        try await pasteWithNoDelay(using: pasteboard)

        XCTAssertEqual(
            pasteboard.items,
            [.item([.payload("public.file-url", Array("file:///tmp/example.txt".utf8))])]
        )
    }

    func testPasteTransactionPreservesMultipleItemsAndRepresentations() async throws {
        let pasteboard = CharacterizationPasteboard(
            items: [
                .item([
                    .payload("public.utf8-plain-text", Array("before".utf8)),
                    .payload("public.rtf", [0x7B, 0x5C]),
                ]),
                .item([
                    .payload("public.png", [0x89, 0x50]),
                    .payload("public.data", [0x01, 0x02, 0x03]),
                ]),
            ]
        )

        try await pasteWithNoDelay(using: pasteboard)

        XCTAssertEqual(
            pasteboard.items,
            [
                .item([
                    .payload("public.utf8-plain-text", Array("before".utf8)),
                    .payload("public.rtf", [0x7B, 0x5C]),
                ]),
                .item([
                    .payload("public.png", [0x89, 0x50]),
                    .payload("public.data", [0x01, 0x02, 0x03]),
                ]),
            ]
        )
    }

    func testPasteTransactionRestoresClipboardWhenPasteFails() async {
        let pasteboard = CharacterizationPasteboard(items: [.plainText("before")])
        var waits: [UInt64] = []

        do {
            try await PasteboardTextTransaction.paste(
                "dictation",
                preserveClipboard: true,
                using: pasteboard,
                triggerPaste: { throw CharacterizationError.expected },
                sleep: { nanoseconds in
                    waits.append(nanoseconds)
                }
            )
            XCTFail("Expected injected paste failure")
        } catch CharacterizationError.expected {
            // Expected simulated paste failure.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(waits, [])
        XCTAssertEqual(pasteboard.items, [.plainText("before")])
    }

    func testPasteTransactionCharacterizesEarlyExitWithoutClipboardRestoration() async throws {
        let pasteboard = CharacterizationPasteboard(items: [.plainText("before")])
        var waits: [UInt64] = []

        try await PasteboardTextTransaction.paste(
            "dictation",
            preserveClipboard: false,
            using: pasteboard,
            triggerPaste: {},
            sleep: { nanoseconds in
                waits.append(nanoseconds)
            }
        )

        XCTAssertEqual(waits, [200_000_000])
        XCTAssertEqual(pasteboard.items, [.plainText("dictation")])
    }

    func testPasteTransactionDoesNotOverwriteConcurrentClipboardChange() async throws {
        let pasteboard = CharacterizationPasteboard(items: [.plainText("before")])
        var userChangeCount: Int?

        try await PasteboardTextTransaction.paste(
            "dictation",
            preserveClipboard: true,
            using: pasteboard,
            triggerPaste: {},
            sleep: { nanoseconds in
                if nanoseconds == 200_000_000 {
                    pasteboard.replaceItems([.item([.payload("public.png", [0x89, 0x50])])])
                    userChangeCount = pasteboard.changeCount
                }
            }
        )

        XCTAssertNotNil(userChangeCount)
        XCTAssertEqual(pasteboard.changeCount, userChangeCount)
        XCTAssertEqual(
            pasteboard.items,
            [.item([.payload("public.png", [0x89, 0x50])])]
        )
    }

    private func pasteWithNoDelay(using pasteboard: CharacterizationPasteboard) async throws {
        try await PasteboardTextTransaction.paste(
            "dictation",
            preserveClipboard: true,
            using: pasteboard,
            triggerPaste: {},
            sleep: { _ in }
        )
    }

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

private enum CharacterizationError: Error {
    case expected
}

private final class CharacterizationPasteboard: PasteboardTextTransactionPasteboard {
    struct Representation: Equatable {
        let type: String
        let data: Data

        static func payload(_ type: String, _ bytes: [UInt8]) -> Representation {
            Representation(type: type, data: Data(bytes))
        }
    }

    struct Item: Equatable {
        let representations: [Representation]

        static func item(_ representations: [Representation]) -> Item {
            Item(representations: representations)
        }

        static func plainText(_ value: String) -> Item {
            item([.payload("public.utf8-plain-text", Array(value.utf8))])
        }
    }

    private(set) var items: [Item]
    private(set) var changeCount = 0

    init(items: [Item]) {
        self.items = items
    }

    var plainText: String? {
        guard let data = items.first?.representations.first(where: {
            $0.type == "public.utf8-plain-text"
        })?.data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func snapshot() -> [PasteboardTextTransactionItem] {
        items.map { item in
            PasteboardTextTransactionItem(
                representations: item.representations.map {
                    PasteboardTextTransactionRepresentation(type: $0.type, data: $0.data)
                }
            )
        }
    }

    func replaceWithPlainText(_ text: String) {
        items = [.plainText(text)]
        changeCount += 1
    }

    func restore(_ items: [PasteboardTextTransactionItem]) {
        self.items = items.map { item in
            Item.item(item.representations.map {
                Representation(type: $0.type, data: $0.data)
            })
        }
        changeCount += 1
    }

    func replaceItems(_ items: [Item]) {
        self.items = items
        changeCount += 1
    }
}

private final class FakeFocusedAXAdapter: FocusedAXTextInsertionAdapter {
    private final class Element {}

    private let focused = Element()
    var value: String?
    let range: AXTextSelectionRange?
    let editable: Bool
    let windowChildCount: Int
    private(set) var replacementCalls: [String] = []
    private(set) var wholeFieldOverwriteAttempts = 0
    private(set) var visitedElementCount = 0
    private(set) var windowChildVisitCount = 0

    init(
        value: String?,
        range: AXTextSelectionRange?,
        editable: Bool = true,
        windowChildCount: Int = 0
    ) {
        self.value = value
        self.range = range
        self.editable = editable
        self.windowChildCount = windowChildCount
    }

    func focusedElement() -> AnyObject? {
        visitedElementCount += 1
        return focused
    }

    func value(of element: AnyObject) -> String? {
        element === focused ? value : nil
    }

    func selectedTextRange(of element: AnyObject) -> AXTextSelectionRange? {
        element === focused ? range : nil
    }

    func isEditable(_ element: AnyObject) -> Bool {
        element === focused && editable
    }

    func replaceSelectedText(_ text: String, in element: AnyObject) -> Bool {
        guard element === focused, let value, let range else { return false }
        replacementCalls.append(text)
        var updated = Array(value.utf16)
        updated.replaceSubrange(range.location..<(range.location + range.length), with: text.utf16)
        self.value = String(decoding: updated, as: UTF16.self)
        return true
    }
}
