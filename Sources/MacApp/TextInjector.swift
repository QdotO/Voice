import AppKit
import Carbon.HIToolbox

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
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Type text character by character into the active app
    func type(_ text: String) throws {
        guard Self.isAccessibilityEnabled else {
            throw InjectionError.accessibilityNotEnabled
        }

        for char in text {
            try typeCharacter(char)
            // Small delay to prevent dropped characters
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    /// Paste text using clipboard (faster for long text)
    func paste(_ text: String) throws {
        guard Self.isAccessibilityEnabled else {
            throw InjectionError.accessibilityNotEnabled
        }

        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        try simulateKeyPress(
            keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand, tap: .cgSessionEventTap)

        // Allow enough time for the target app to read from the clipboard
        Thread.sleep(forTimeInterval: 0.2)

        // Restore previous clipboard after a short delay
        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    /// Insert text into the currently focused UI element via Accessibility
    func insertIntoFocusedElement(_ text: String) throws {
        guard Self.isAccessibilityEnabled else {
            throw InjectionError.accessibilityNotEnabled
        }

        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusedStatus == .success, let focusedElement = focused else {
            throw InjectionError.focusedElementNotFound
        }

        let axElement = focusedElement as! AXUIElement
        guard tryInsertText(text, into: axElement) else {
            throw InjectionError.focusedElementNotEditable
        }
    }

    /// Advanced Accessibility insertion that falls back to searching the focused window
    func insertIntoFocusedElementAdvanced(_ text: String) throws -> Bool {
        guard Self.isAccessibilityEnabled else {
            throw InjectionError.accessibilityNotEnabled
        }

        let system = AXUIElementCreateSystemWide()
        if let focused = copyAttribute(system, attribute: kAXFocusedUIElementAttribute as CFString)
        {
            let element = focused as! AXUIElement
            if tryInsertText(text, into: element) {
                return true
            }
        }

        if let focusedWindow = copyAttribute(
            system, attribute: kAXFocusedWindowAttribute as CFString)
        {
            let windowElement = focusedWindow as! AXUIElement
            if let target = findEditableElement(in: windowElement, maxDepth: 5, maxNodes: 300) {
                if tryInsertText(text, into: target) {
                    return true
                }
            }
        }

        return false
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

    private func tryInsertText(_ text: String, into element: AXUIElement) -> Bool {
        if AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
        {
            return true
        }

        if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
            == .success
        {
            return true
        }

        return false
    }

    private func copyAttribute(_ element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return value
    }

    private func findEditableElement(
        in root: AXUIElement,
        maxDepth: Int,
        maxNodes: Int
    ) -> AXUIElement? {
        let editableRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField",
        ]

        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0

        while !queue.isEmpty, visited < maxNodes {
            let (element, depth) = queue.removeFirst()
            visited += 1

            if isEditable(element, roles: editableRoles) {
                return element
            }

            guard depth < maxDepth else { continue }
            if let children = copyAttribute(element, attribute: kAXChildrenAttribute as CFString)
                as? [AXUIElement]
            {
                for child in children {
                    queue.append((child, depth + 1))
                }
            }
        }

        return nil
    }

    private func isEditable(_ element: AXUIElement, roles: Set<String>) -> Bool {
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            == .success,
            let role = roleRef as? String,
            roles.contains(role)
        {
            var settable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
                == .success,
                settable.boolValue
            {
                return true
            }
            if AXUIElementIsAttributeSettable(
                element, kAXSelectedTextAttribute as CFString, &settable) == .success,
                settable.boolValue
            {
                return true
            }
        }

        return false
    }
}
