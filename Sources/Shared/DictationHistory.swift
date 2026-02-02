import Foundation

public struct DictationHistoryEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let durationSeconds: Double
    public let model: String
    public let outputMethod: String

    public init(text: String, durationSeconds: Double, model: String, outputMethod: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.durationSeconds = durationSeconds
        self.model = model
        self.outputMethod = outputMethod
    }
}

public final class DictationHistory {
    public static let shared = DictationHistory()
    public static let didChangeNotification = Notification.Name("DictationHistoryDidChange")

    private var entries: [DictationHistoryEntry] = []
    private let fileURL: URL
    private let maxEntries = 100

    private init() {
        let baseURL = SharedStorage.baseDirectory()
        let appDir = baseURL.appendingPathComponent("Whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("dictation-history.json")
        load()
    }

    public func allEntries() -> [DictationHistoryEntry] {
        entries.sorted { $0.timestamp > $1.timestamp }
    }

    public func addEntry(text: String, durationSeconds: Double, model: String, outputMethod: String) {
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([DictationHistoryEntry].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
}
