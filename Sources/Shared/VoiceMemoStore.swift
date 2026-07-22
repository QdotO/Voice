import Foundation
import OSLog

/// Synchronous facade over thread-safe SQLite storage. Cache snapshot uses
/// `LockedSnapshot`; SQLite work and caller update closures never run under its lock.
public final class VoiceMemoStore: @unchecked Sendable {
    public static let shared = VoiceMemoStore(baseURL: VoiceMemoStore.defaultBaseURL())
    public static let didChangeNotification = Notification.Name("VoiceMemoStoreDidChange")
    private static let logger = Logger(subsystem: "Whisper", category: "VoiceMemoStore")

    private let memos: LockedSnapshot<[VoiceMemo]>
    private let storage: SQLiteV2Store
    private let memosDir: URL

    public init(baseURL: URL) {
        memos = LockedSnapshot([])
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
        do {
            let current = try storage.fetchMemos()
            memos.replace(with: current)
            return sorted(current)
        } catch {
            Self.logger.error(
                "Failed to read voice memos: \(error.localizedDescription, privacy: .public)")
            return sorted(memos.read())
        }
    }

    public func add(_ memo: VoiceMemo) {
        do {
            try storage.upsertMemo(memo)
            memos.withValue { current in
                current.removeAll { $0.id == memo.id }
                current.append(memo)
            }
            postChangeNotification()
        } catch {
            Self.logger.error(
                "Failed to save voice memos: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func update(id: UUID, block: (inout VoiceMemo) -> Void) {
        do {
            guard let updated = try storage.updateMemo(id: id, block: block) else { return }
            memos.withValue { current in
                current.removeAll { $0.id == id }
                current.append(updated)
            }
            postChangeNotification()
        } catch {
            Self.logger.error(
                "Failed to save voice memos: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func remove(id: UUID) {
        do {
            try storage.deleteMemo(id: id)
            memos.withValue { current in
                current.removeAll { $0.id == id }
            }
            // Preserve existing contract: remove missing id still posts after successful save.
            postChangeNotification()
        } catch {
            Self.logger.error(
                "Failed to save voice memos: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func memoURL(for memo: VoiceMemo) -> URL {
        memosDir.appendingPathComponent(memo.audioFileName)
    }

    private func load() {
        do {
            memos.replace(with: try storage.fetchMemos())
        } catch {
            Self.logger.error(
                "Failed to load voice memos: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sorted(_ memos: [VoiceMemo]) -> [VoiceMemo] {
        memos.sorted { $0.createdAt > $1.createdAt }
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
