import Foundation

public struct PasteboardTextTransactionRepresentation: Equatable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

public struct PasteboardTextTransactionItem: Equatable {
    public let representations: [PasteboardTextTransactionRepresentation]

    public init(representations: [PasteboardTextTransactionRepresentation]) {
        self.representations = representations
    }
}

/// Minimal clipboard surface used by the paste transaction.
///
/// This is public because the macOS executable and SwiftPM test target are separate
/// modules. Snapshot data is copied so restoration can reproduce every item and
/// representation without depending on live NSPasteboard objects.
public protocol PasteboardTextTransactionPasteboard: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> [PasteboardTextTransactionItem]

    func replaceWithPlainText(_ text: String)
    func restore(_ items: [PasteboardTextTransactionItem])
}

/// Runs Whisper's paste and delayed-restore lifecycle.
public enum PasteboardTextTransaction {
    public static func paste(
        _ text: String,
        preserveClipboard: Bool,
        using pasteboard: PasteboardTextTransactionPasteboard,
        triggerPaste: () throws -> Void,
        sleep: (UInt64) async throws -> Void
    ) async throws {
        let previousContents = preserveClipboard ? pasteboard.snapshot() : []

        pasteboard.replaceWithPlainText(text)
        let temporaryChangeCount = pasteboard.changeCount
        var restorationAttempted = false

        defer {
            if preserveClipboard, !restorationAttempted,
                pasteboard.changeCount == temporaryChangeCount
            {
                pasteboard.restore(previousContents)
            }
        }

        try triggerPaste()
        try await sleep(200_000_000)

        guard preserveClipboard else { return }

        try await sleep(300_000_000)

        guard pasteboard.changeCount == temporaryChangeCount else {
            restorationAttempted = true
            return
        }

        pasteboard.restore(previousContents)
        restorationAttempted = true
    }

    public static func pasteSynchronously(
        _ text: String,
        preserveClipboard: Bool,
        using pasteboard: PasteboardTextTransactionPasteboard,
        triggerPaste: () throws -> Void,
        sleep: (TimeInterval) -> Void
    ) throws {
        let previousContents = preserveClipboard ? pasteboard.snapshot() : []

        pasteboard.replaceWithPlainText(text)
        let temporaryChangeCount = pasteboard.changeCount
        var restorationAttempted = false

        defer {
            if preserveClipboard, !restorationAttempted,
                pasteboard.changeCount == temporaryChangeCount
            {
                pasteboard.restore(previousContents)
            }
        }

        try triggerPaste()
        sleep(0.2)

        guard preserveClipboard else { return }

        sleep(0.3)

        guard pasteboard.changeCount == temporaryChangeCount else {
            restorationAttempted = true
            return
        }

        pasteboard.restore(previousContents)
        restorationAttempted = true
    }
}
