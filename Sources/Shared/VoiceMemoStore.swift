import Foundation
import OSLog

public final class VoiceMemoStore {
    public static let shared = VoiceMemoStore(baseURL: VoiceMemoStore.defaultBaseURL())
    public static let didChangeNotification = Notification.Name("VoiceMemoStoreDidChange")
    private static let logger = Logger(subsystem: "Whisper", category: "VoiceMemoStore")

    private var memos: [VoiceMemo] = []
    private let storage: SQLiteV2Store
    private let memosDir: URL

    public init(baseURL: URL) {
        storage = SQLiteV2Store.shared(baseURL: baseURL)
        memosDir = storage.paths.voiceMemosDirectory
        load()
    }

    public static func makeInDirectory(_ url: URL) -> VoiceMemoStore {
        VoiceMemoStore(baseURL: url)
    }

    private static func defaultBaseURL() -> URL {
        SharedStorage.baseDirectory()
    }

    public var directory: URL {
        memosDir
    }

    public func allMemos() -> [VoiceMemo] {
        memos.sorted { $0.createdAt > $1.createdAt }
    }

    public func add(_ memo: VoiceMemo) {
        memos.append(memo)
        save()
    }

    public func update(id: UUID, block: (inout VoiceMemo) -> Void) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else { return }
        block(&memos[index])
        save()
    }

    public func remove(id: UUID) {
        memos.removeAll { $0.id == id }
        save()
    }

    public func memoURL(for memo: VoiceMemo) -> URL {
        memosDir.appendingPathComponent(memo.audioFileName)
    }

    private func load() {
        do {
            memos = try storage.fetchMemos()
        } catch {
            Self.logger.error(
                "Failed to load voice memos: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            try storage.replaceMemos(memos)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        } catch {
            Self.logger.error(
                "Failed to save voice memos: \(error.localizedDescription, privacy: .public)")
        }
    }
}
