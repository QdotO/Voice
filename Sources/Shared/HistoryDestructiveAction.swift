import Foundation

/// Pending irreversible history/correction action. Storage changes happen only after confirmation.
public enum HistoryDestructiveAction: Identifiable, Equatable, Sendable {
    case deleteTranscriptions(ids: [UUID])
    case deleteCorrections(ids: [UUID])
    case clearHistory(count: Int)
    case clearCorrections(count: Int)

    public var id: String {
        switch self {
        case .deleteTranscriptions(let ids):
            return "delete-transcriptions-" + ids.map(\.uuidString).joined(separator: ",")
        case .deleteCorrections(let ids):
            return "delete-corrections-" + ids.map(\.uuidString).joined(separator: ",")
        case .clearHistory(let count):
            return "clear-history-\(count)"
        case .clearCorrections(let count):
            return "clear-corrections-\(count)"
        }
    }

    public var title: String {
        switch self {
        case .deleteTranscriptions:
            return "Delete transcription?"
        case .deleteCorrections:
            return "Delete learned correction?"
        case .clearHistory:
            return "Clear all History?"
        case .clearCorrections:
            return "Clear all Corrections?"
        }
    }

    public var message: String {
        switch self {
        case .deleteTranscriptions:
            return "This removes this transcription from History. This cannot be undone."
        case .deleteCorrections:
            return "Whisper will no longer apply this correction. This cannot be undone."
        case .clearHistory(let count):
            return "This removes \(count) transcriptions. This cannot be undone."
        case .clearCorrections(let count):
            return "This removes \(count) learned corrections. This cannot be undone."
        }
    }

    public var confirmButtonTitle: String {
        switch self {
        case .deleteTranscriptions, .deleteCorrections:
            return "Delete"
        case .clearHistory:
            return "Clear History"
        case .clearCorrections:
            return "Clear Corrections"
        }
    }
}
