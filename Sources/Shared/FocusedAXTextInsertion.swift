import Foundation

/// UTF-16 selection range reported by an accessibility text element.
public struct AXTextSelectionRange: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public func isValid(forUTF16Length valueLength: Int) -> Bool {
        guard location >= 0, length >= 0, location <= valueLength else { return false }
        return length <= valueLength - location
    }
}

/// Small seam around platform AX calls. Production code supplies AppKit adapter;
/// tests supply fake focused elements.
public protocol FocusedAXTextInsertionAdapter: AnyObject {
    func focusedElement() -> AnyObject?
    func value(of element: AnyObject) -> String?
    func selectedTextRange(of element: AnyObject) -> AXTextSelectionRange?
    func isEditable(_ element: AnyObject) -> Bool
    func replaceSelectedText(_ text: String, in element: AnyObject) -> Bool
}

/// Replaces selection in focused element only. No window traversal or whole-value write.
public final class FocusedAXTextInserter {
    private let adapter: any FocusedAXTextInsertionAdapter

    public init(adapter: any FocusedAXTextInsertionAdapter) {
        self.adapter = adapter
    }

    public func insert(_ text: String) -> Bool {
        guard let element = adapter.focusedElement(), adapter.isEditable(element),
            let value = adapter.value(of: element),
            let range = adapter.selectedTextRange(of: element),
            range.isValid(forUTF16Length: value.utf16.count)
        else {
            return false
        }

        return adapter.replaceSelectedText(text, in: element)
    }
}
