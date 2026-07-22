import Foundation
import OSLog

public struct DictationHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let durationSeconds: Double
    public let model: String
    public let outputMethod: String

    public init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        durationSeconds: Double,
        model: String,
        outputMethod: String
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.model = model
        self.outputMethod = outputMethod
    }
}

/// Synchronous facade over thread-safe SQLite storage with immutable configuration.
public final class DictationHistory: @unchecked Sendable {
    public static let shared = DictationHistory()
    public static let didChangeNotification = Notification.Name("DictationHistoryDidChange")
    private static let logger = Logger(subsystem: "Whisper", category: "DictationHistory")

    private let storage: SQLiteV2Store
    private let maxEntries = 100

    private init() {
        storage = SQLiteV2Store.shared()
    }

    /// Testable initializer — uses a custom directory for isolation
    init(baseURL: URL) {
        storage = SQLiteV2Store.shared(baseURL: baseURL)
    }

    public func allEntries() -> [DictationHistoryEntry] {
        do {
            return try storage.fetchHistoryEntries().sorted { $0.timestamp > $1.timestamp }
        } catch {
            Self.logger.error("Failed to load history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func addEntry(text: String, durationSeconds: Double, model: String, outputMethod: String)
    {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = DictationHistoryEntry(
            text: trimmed,
            durationSeconds: durationSeconds,
            model: model,
            outputMethod: outputMethod
        )

        do {
            try storage.upsertHistoryEntryAndTrim(entry, maxEntries: maxEntries)
            postChangeNotification()
        } catch {
            logStorageError("save", error: error)
        }
    }

    public func entry(id: UUID) -> DictationHistoryEntry? {
        allEntries().first { $0.id == id }
    }

    public func remove(id: UUID) {
        do {
            try storage.deleteHistoryEntry(id: id)
            postChangeNotification()
        } catch {
            logStorageError("delete", error: error)
        }
    }

    public func clear() {
        do {
            try storage.deleteAllHistory()
            postChangeNotification()
        } catch {
            logStorageError("clear", error: error)
        }
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func logStorageError(_ operation: String, error: Error) {
        Self.logger.error(
            "Failed to \(operation) history: \(error.localizedDescription, privacy: .public)"
        )
    }
}
