import Foundation

public final class VoiceMemoStore {
    public static let shared = VoiceMemoStore(baseURL: VoiceMemoStore.defaultBaseURL())
    public static let didChangeNotification = Notification.Name("VoiceMemoStoreDidChange")

    private var memos: [VoiceMemo] = []
    private let fileURL: URL
    private let memosDir: URL

    public init(baseURL: URL) {
        let appDir = baseURL.appendingPathComponent("Whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        memosDir = appDir.appendingPathComponent("voice-memos", isDirectory: true)
        try? FileManager.default.createDirectory(at: memosDir, withIntermediateDirectories: true)

        fileURL = appDir.appendingPathComponent("voice-memos.json")
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            memos = try JSONDecoder().decode([VoiceMemo].self, from: data)
        } catch {
            print("Failed to load voice memos: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(memos)
            try data.write(to: fileURL)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        } catch {
            print("Failed to save voice memos: \(error)")
        }
    }
}
