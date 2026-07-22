import Foundation
import XCTest

@testable import WhisperShared

@MainActor
final class VoiceMemoManagerTests: XCTestCase {
    func testStopRecordingWithoutStartIsNoOp() {
        let manager = makeManager(store: VoiceMemoStore.makeInDirectory(makeTempDir()))

        manager.stopRecording()

        XCTAssertFalse(manager.isRecording)
        XCTAssertEqual(manager.memos, [])
    }

    func testTogglePlaybackForMissingAudioLeavesPlaybackStopped() {
        let store = VoiceMemoStore.makeInDirectory(makeTempDir())
        let memo = makeMemo(audioFileName: "missing.m4a")
        store.add(memo)
        let manager = makeManager(store: store)

        manager.togglePlayback(for: memo)

        XCTAssertNil(manager.currentlyPlayingID)
        XCTAssertEqual(manager.playbackTime, 0)
        XCTAssertEqual(manager.playbackDuration, 0)
    }

    func testDeleteRemovesAudioBeforeMetadata() throws {
        let store = VoiceMemoStore.makeInDirectory(makeTempDir())
        let memo = makeMemo(audioFileName: "memo.m4a")
        store.add(memo)
        let audioURL = store.memoURL(for: memo)
        try Data("audio".utf8).write(to: audioURL)
        let manager = makeManager(store: store)

        let result = manager.deleteMemo(memo)

        XCTAssertEqual(result, .deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertTrue(manager.memos.isEmpty)
    }

    func testDeleteMissingAudioRemovesMetadataWithExplicitOutcome() {
        let store = VoiceMemoStore.makeInDirectory(makeTempDir())
        let memo = makeMemo(audioFileName: "missing.m4a")
        store.add(memo)
        let manager = makeManager(store: store)

        let result = manager.deleteMemo(memo)

        XCTAssertEqual(result, .deletedRecordAudioMissing)
        XCTAssertTrue(manager.memos.isEmpty)
    }

    func testDeleteDirectoryAudioRemovesMetadata() throws {
        let store = VoiceMemoStore.makeInDirectory(makeTempDir())
        let memo = makeMemo(audioFileName: "audio-directory")
        store.add(memo)
        let audioURL = store.memoURL(for: memo)
        try FileManager.default.createDirectory(at: audioURL, withIntermediateDirectories: true)
        try Data("keep directory non-empty".utf8)
            .write(to: audioURL.appendingPathComponent("child"))
        let manager = makeManager(store: store)

        let result = manager.deleteMemo(memo)

        XCTAssertEqual(result, .deleted)
        XCTAssertTrue(manager.memos.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testExportCopiesAudioAndReturnsDestination() throws {
        let store = VoiceMemoStore.makeInDirectory(makeTempDir())
        let memo = makeMemo(audioFileName: "memo.m4a")
        store.add(memo)
        try Data("audio".utf8).write(to: store.memoURL(for: memo))
        let destination = makeTempDir().appendingPathComponent("exported.m4a")
        let manager = makeManager(store: store)

        let result = manager.exportMemo(memo, to: destination)

        XCTAssertEqual(result, .exported(destination))
        XCTAssertEqual(try Data(contentsOf: destination), Data("audio".utf8))
    }

    func testExportMissingAudioReturnsTypedFailure() {
        let store = VoiceMemoStore.makeInDirectory(makeTempDir())
        let memo = makeMemo(audioFileName: "missing.m4a")
        store.add(memo)
        let manager = makeManager(store: store)
        let destination = makeTempDir().appendingPathComponent("exported.m4a")

        let result = manager.exportMemo(memo, to: destination)

        XCTAssertEqual(result, .sourceAudioMissing(store.memoURL(for: memo)))
    }

    func testExportCopyFailureReturnsTypedFailure() throws {
        let store = VoiceMemoStore.makeInDirectory(makeTempDir())
        let memo = makeMemo(audioFileName: "memo.m4a")
        store.add(memo)
        let sourceURL = store.memoURL(for: memo)
        try Data("audio".utf8).write(to: sourceURL)
        let destination = makeTempDir().appendingPathComponent("existing.m4a")
        try Data("existing".utf8).write(to: destination)
        let manager = makeManager(store: store)

        let result = manager.exportMemo(memo, to: destination)

        guard case .failed(.copyFailed(let source, let failedDestination, _)) = result else {
            return XCTFail("Expected typed copy failure, got \(result)")
        }
        XCTAssertEqual(source, sourceURL)
        XCTAssertEqual(failedDestination, destination)
    }

    func testRetranscribeUsesSharedEngineAndStoresTranscript() async throws {
        let tempDir = makeTempDir()
        let store = VoiceMemoStore.makeInDirectory(tempDir)
        let memo = VoiceMemo(
            id: UUID(),
            title: "Memo",
            createdAt: Date(),
            durationSeconds: 1.0,
            audioFileName: "memo.m4a",
            transcript: nil,
            transcriptWords: nil,
            isTranscribing: false,
            autoTranscribe: true
        )
        store.add(memo)

        let fakeEngine = FakeWhisperEngine(
            memoResults: [
                .success(
                    MemoTranscriptionResult(
                        memoID: memo.id,
                        payload: TranscriptionPayload(
                            text: "hello world",
                            words: [
                                TranscriptWord(word: "hello", start: 0, end: 0.4),
                                TranscriptWord(word: "world", start: 0.5, end: 0.9),
                            ]
                        ),
                        durationSeconds: 0.9
                    )
                )
            ]
        )
        let settingsStore = InMemorySettingsStore(
            settings: WhisperSettings(
                selectedProfile: .accurate,
                rawModelOverride: "small-custom"
            )
        )
        let manager = VoiceMemoManager(
            engine: fakeEngine,
            settingsStore: settingsStore,
            promptProvider: { "SwiftUI, Whisper" },
            store: store
        )

        manager.retranscribe(memo)
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            let currentMemo = manager.memos.first(where: { $0.id == memo.id })
            return currentMemo?.isTranscribing == false && currentMemo?.transcript == "hello world"
        }

        let updated = manager.memos.first(where: { $0.id == memo.id })
        let preparations = await fakeEngine.recordedPreparations()
        let requests = await fakeEngine.recordedMemoRequests()

        XCTAssertEqual(updated?.transcript, "hello world")
        XCTAssertEqual(updated?.transcriptWords?.count, 2)
        XCTAssertEqual(updated?.durationSeconds, 0.9)
        XCTAssertEqual(
            preparations,
            [WhisperEnginePreparation(profile: .accurate, rawModelOverride: "small-custom")]
        )
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.memoID, memo.id)
        XCTAssertEqual(requests.first?.prompt, "SwiftUI, Whisper")
    }

    func testRetranscribeFailureClearsTranscriptionState() async throws {
        let store = VoiceMemoStore.makeInDirectory(makeTempDir())
        let memo = makeMemo(
            transcript: "old transcript",
            transcriptWords: [TranscriptWord(word: "old", start: 0, end: 0.2)]
        )
        store.add(memo)
        let fakeEngine = FakeWhisperEngine(
            memoResults: [.failure(.scripted("inference failed"))]
        )
        let manager = VoiceMemoManager(
            engine: fakeEngine,
            settingsStore: InMemorySettingsStore(),
            promptProvider: { "" },
            store: store
        )

        manager.retranscribe(memo)
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            manager.memos.first?.isTranscribing == false
        }

        let updated = manager.memos.first
        XCTAssertNil(updated?.transcript)
        XCTAssertNil(updated?.transcriptWords)
        XCTAssertFalse(updated?.isTranscribing ?? true)
    }

    func testRetranscribeMissingTimingsQueuesEveryTarget() async throws {
        let tempDir = makeTempDir()
        let store = VoiceMemoStore.makeInDirectory(tempDir)
        let olderMemo = VoiceMemo(
            id: UUID(),
            title: "Older",
            createdAt: Date(timeIntervalSince1970: 1),
            durationSeconds: 1.0,
            audioFileName: "older.m4a",
            transcript: "older",
            transcriptWords: nil,
            isTranscribing: false,
            autoTranscribe: true
        )
        let newerMemo = VoiceMemo(
            id: UUID(),
            title: "Newer",
            createdAt: Date(timeIntervalSince1970: 2),
            durationSeconds: 1.0,
            audioFileName: "newer.m4a",
            transcript: "newer",
            transcriptWords: nil,
            isTranscribing: false,
            autoTranscribe: true
        )
        store.add(olderMemo)
        store.add(newerMemo)

        let fakeEngine = FakeWhisperEngine(
            memoResults: [
                .success(
                    MemoTranscriptionResult(
                        memoID: newerMemo.id,
                        payload: TranscriptionPayload(
                            text: "newer transcript",
                            words: [TranscriptWord(word: "newer", start: 0, end: 0.3)]
                        ),
                        durationSeconds: 1.0
                    )
                ),
                .success(
                    MemoTranscriptionResult(
                        memoID: olderMemo.id,
                        payload: TranscriptionPayload(
                            text: "older transcript",
                            words: [TranscriptWord(word: "older", start: 0, end: 0.3)]
                        ),
                        durationSeconds: 1.0
                    )
                ),
            ]
        )
        let manager = VoiceMemoManager(
            engine: fakeEngine,
            settingsStore: InMemorySettingsStore(),
            promptProvider: { "" },
            store: store
        )

        manager.retranscribeMissingTimings()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            manager.memos.allSatisfy { !$0.isTranscribing && !($0.transcriptWords?.isEmpty ?? true) }
        }

        let requests = await fakeEngine.recordedMemoRequests()
        XCTAssertEqual(requests.map { $0.memoID }, [newerMemo.id, olderMemo.id])
    }

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeMemo(
        audioFileName: String = "memo.m4a",
        transcript: String? = nil,
        transcriptWords: [TranscriptWord]? = nil
    ) -> VoiceMemo {
        VoiceMemo(
            id: UUID(),
            title: "Memo",
            createdAt: Date(),
            durationSeconds: 1,
            audioFileName: audioFileName,
            transcript: transcript,
            transcriptWords: transcriptWords,
            isTranscribing: false,
            autoTranscribe: true
        )
    }

    private func makeManager(store: VoiceMemoStore) -> VoiceMemoManager {
        VoiceMemoManager(
            engine: FakeWhisperEngine(),
            settingsStore: InMemorySettingsStore(),
            promptProvider: { "" },
            store: store
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while !condition() {
            if start.duration(to: .now) > .nanoseconds(Int64(timeoutNanoseconds)) {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
