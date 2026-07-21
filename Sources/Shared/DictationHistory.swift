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

public final class DictationHistory {
    public static let shared = DictationHistory()
    public static let didChangeNotification = Notification.Name("DictationHistoryDidChange")
    private static let logger = Logger(subsystem: "Whisper", category: "DictationHistory")

    private var entries: [DictationHistoryEntry] = []
    private let storage: SQLiteV2Store
    private let maxEntries = 100

    private init() {
        storage = SQLiteV2Store.shared()
        load()
    }

    /// Testable initializer — uses a custom directory for isolation
    init(baseURL: URL) {
        storage = SQLiteV2Store.shared(baseURL: baseURL)
        load()
    }

    public func allEntries() -> [DictationHistoryEntry] {
        entries.sorted { $0.timestamp > $1.timestamp }
    }

    public func addEntry(text: String, durationSeconds: Double, model: String, outputMethod: String)
    {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        entries.append(
            DictationHistoryEntry(
                text: trimmed,
                durationSeconds: durationSeconds,
                model: model,
                outputMethod: outputMethod
            ))

        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }

        save()
    }

    public func entry(id: UUID) -> DictationHistoryEntry? {
        entries.first { $0.id == id }
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        do {
            entries = try storage.fetchHistoryEntries()
        } catch {
            Self.logger.error("Failed to load history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            try storage.replaceHistoryEntries(entries)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        } catch {
            Self.logger.error("Failed to save history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
