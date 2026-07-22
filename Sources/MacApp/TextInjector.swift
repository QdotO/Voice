import AppKit
import Carbon.HIToolbox
import WhisperShared

private final class AppKitPasteboardAdapter: PasteboardTextTransactionPasteboard {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func snapshot() -> [PasteboardTextTransactionItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            PasteboardTextTransactionItem(
                representations: item.types.compactMap { type in
                    guard let data = item.data(forType: type) else { return nil }
                    return PasteboardTextTransactionRepresentation(
                        type: type.rawValue,
                        data: data
                    )
                }
            )
        }
    }

    func replaceWithPlainText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func restore(_ items: [PasteboardTextTransactionItem]) {
        pasteboard.clearContents()

        let pasteboardItems = items.map { item in
            let pasteboardItem = NSPasteboardItem()
            for representation in item.representations {
                pasteboardItem.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(representation.type)
                )
            }
            return pasteboardItem
        }

        if !pasteboardItems.isEmpty {
            pasteboard.writeObjects(pasteboardItems)
        }
    }
}

private final class AppKitAXElementToken {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }
}

private final class AppKitFocusedAXTextInsertionAdapter: FocusedAXTextInsertionAdapter {
    func focusedElement() -> AnyObject? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused else {
            return nil
        }

        return AppKitAXElementToken(focused as! AXUIElement)
    }

    func value(of element: AnyObject) -> String? {
        guard let element = element as? AppKitAXElementToken else { return nil }
        return copyAttribute(element.element, kAXValueAttribute as CFString) as? String
    }

    func selectedTextRange(of element: AnyObject) -> AXTextSelectionRange? {
        guard let element = element as? AppKitAXElementToken,
            let rawValue = copyAttribute(element.element, kAXSelectedTextRangeAttribute as CFString)
        else {
            return nil
        }
        let value = rawValue as! AXValue
        guard AXValueGetType(value) == .cfRange else { return nil }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return AXTextSelectionRange(location: range.location, length: range.length)
    }

    func isEditable(_ element: AnyObject) -> Bool {
        guard let element = element as? AppKitAXElementToken else { return false }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            element.element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }

    func replaceSelectedText(_ text: String, in element: AnyObject) -> Bool {
        guard let element = element as? AppKitAXElementToken else { return false }
        return AXUIElementSetAttributeValue(
            element.element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }
}

/// Injects transcribed text into the active application
final class TextInjector {

    enum InjectionError: Error, LocalizedError {
        case accessibilityNotEnabled
        case eventCreationFailed
        case focusedElementNotFound
        case focusedElementNotEditable

        var errorDescription: String? {
            switch self {
            case .accessibilityNotEnabled:
                return "Accessibility permission not granted"
            case .eventCreationFailed:
                return "Failed to create keyboard event"
            case .focusedElementNotFound:
                return "Focused element not found"
            case .focusedElementNotEditable:
                return "Focused element is not editable"
            }
        }
    }

    /// Check if accessibility is enabled
    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    /// Request accessibility permission
    static func requestAccessibility() {
        // SDK exposes kAXTrustedCheckOptionPrompt as mutable global state. Use its
        // documented CFDictionary key value to avoid crossing that unsafe global.
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Type text without blocking the main thread between key events.
    func typeText(_ text: String) async throws {
        guard Self.isAccessibilityEnabled else {
            throw InjectionError.accessibilityNotEnabled
        }

        for (index, char) in text.enumerated() {
            try typeCharacter(char)
            if index < text.count - 1 {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    /// Paste text while optionally restoring the previous clipboard contents.
    func pasteText(_ text: String, preserveClipboard: Bool = true) async throws {
        guard Self.isAccessibilityEnabled else {
            throw InjectionError.accessibilityNotEnabled
        }

        try await PasteboardTextTransaction.paste(
            text,
            preserveClipboard: preserveClipboard,
            using: AppKitPasteboardAdapter(NSPasteboard.general),
            triggerPaste: {
                try simulateKeyPress(
                    keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand, tap: .cgSessionEventTap)
            },
            sleep: { nanoseconds in
                try await Task.sleep(nanoseconds: nanoseconds)
            }
        )
    }

    /// Accessibility insertion against focused element only. Caller handles paste fallback.
    func insertIntoFocusedElementAdvanced(_ text: String) throws -> Bool {
        guard Self.isAccessibilityEnabled else {
            throw InjectionError.accessibilityNotEnabled
        }

        return FocusedAXTextInserter(adapter: AppKitFocusedAXTextInsertionAdapter()).insert(text)
    }

    // MARK: - Private

    private func typeCharacter(_ char: Character) throws {
        let str = String(char)
        let source = CGEventSource(stateID: .hidSystemState)

        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        else {
            throw InjectionError.eventCreationFailed
        }

        // Set the Unicode character
        var unicodeChar = Array(str.utf16)
        keyDown.keyboardSetUnicodeString(
            stringLength: unicodeChar.count, unicodeString: &unicodeChar)
        keyDown.post(tap: .cghidEventTap)

        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw InjectionError.eventCreationFailed
        }
        keyUp.keyboardSetUnicodeString(stringLength: unicodeChar.count, unicodeString: &unicodeChar)
        keyUp.post(tap: .cghidEventTap)
    }

    private func simulateKeyPress(
        keyCode: UInt16,
        flags: CGEventFlags,
        tap: CGEventTapLocation = .cghidEventTap
    ) throws {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        else {
            throw InjectionError.eventCreationFailed
        }
        keyDown.flags = flags
        keyDown.post(tap: tap)

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw InjectionError.eventCreationFailed
        }
        keyUp.flags = flags
        keyUp.post(tap: tap)
    }

}
