@preconcurrency import AVFoundation
import Foundation
import OSLog
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

public enum VoiceMemoFileOperationError: Error, Equatable, LocalizedError, Sendable {
    case removeFailed(URL, String)
    case copyFailed(source: URL, destination: URL, String)

    public var errorDescription: String? {
        switch self {
        case .removeFailed(let url, let reason):
            return "Could not remove memo audio at \(url.path): \(reason)"
        case .copyFailed(let source, let destination, let reason):
            return "Could not export memo audio from \(source.path) to \(destination.path): \(reason)"
        }
    }
}

public enum VoiceMemoDeleteResult: Equatable, Sendable {
    case deleted
    case deletedRecordAudioMissing
    case failed(VoiceMemoFileOperationError)
}

public enum VoiceMemoExportResult: Equatable, Sendable {
    case cancelled
    case exported(URL)
    case sourceAudioMissing(URL)
    case failed(VoiceMemoFileOperationError)
    case unsupported
}

@MainActor
public final class VoiceMemoManager: NSObject, ObservableObject {
    @Published public private(set) var memos: [VoiceMemo] = []
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentDuration: TimeInterval = 0
    @Published public private(set) var currentlyPlayingID: UUID?
    @Published public private(set) var recordingLevel: Float = 0
    @Published public private(set) var playbackTime: TimeInterval = 0
    @Published public private(set) var playbackDuration: TimeInterval = 0

    private let store: VoiceMemoStore
    private let settingsStore: any SettingsStore
    private let promptProvider: @Sendable () async -> String
    private let logger = Logger(subsystem: "Whisper", category: "VoiceMemos")
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var playbackTimer: Timer?
    private var currentMemoID: UUID?
    private var currentFileURL: URL?
    private let transcriptionQueue: VoiceMemoTranscriptionQueue
    private var transcriptionSubmissionChain: Task<Void, Never>?

    public init(
        engine: any WhisperEngine,
        settingsStore: any SettingsStore,
        promptProvider: @escaping @Sendable () async -> String,
        store: VoiceMemoStore = .shared
    ) {
        self.settingsStore = settingsStore
        self.promptProvider = promptProvider
        self.store = store
        transcriptionQueue = VoiceMemoTranscriptionQueue(engine: engine)
        super.init()
        memos = store.allMemos()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreChange),
            name: VoiceMemoStore.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func startRecording() {
        guard !isRecording else { return }

        let id = UUID()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = "memo-\(timestamp)-\(id.uuidString.prefix(8)).m4a"
        let fileURL = store.directory.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            recorder.record()

            self.recorder = recorder
            currentMemoID = id
            currentFileURL = fileURL
            isRecording = true
            currentDuration = 0

            startTimer()
        } catch {
            logger.error("Failed to start memo recording: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func stopRecording() {
        guard isRecording else { return }

        timer?.invalidate()
        timer = nil

        recorder?.stop()
        let duration = recorder?.currentTime ?? currentDuration
        recorder = nil
        isRecording = false
        recordingLevel = 0

        guard let fileURL = currentFileURL, let memoID = currentMemoID else {
            return
        }

        let title = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .medium,
            timeStyle: .short
        )

        let memo = VoiceMemo(
            id: memoID,
            title: title,
            durationSeconds: duration,
            audioFileName: fileURL.lastPathComponent,
            transcript: nil,
            isTranscribing: true,
            autoTranscribe: true
        )

        store.add(memo)
        memos = store.allMemos()

        if memo.autoTranscribe {
            enqueueTranscription(memoID: memoID, fileURL: fileURL)
        } else {
            store.update(id: memoID) { updated in
                updated.isTranscribing = false
            }
            memos = store.allMemos()
        }
    }

    public func togglePlayback(for memo: VoiceMemo) {
        if currentlyPlayingID == memo.id {
            stopPlayback()
            return
        }

        stopPlayback()

        let url = store.memoURL(for: memo)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            self.player = player
            currentlyPlayingID = memo.id
            playbackDuration = player.duration
            playbackTime = player.currentTime
            startPlaybackTimer()
        } catch {
            logger.error("Failed to play memo: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, player.duration))
        player.currentTime = clamped
        playbackTime = clamped
    }

    @discardableResult
    public func deleteMemo(_ memo: VoiceMemo) -> VoiceMemoDeleteResult {
        if currentlyPlayingID == memo.id {
            stopPlayback()
        }

        let url = store.memoURL(for: memo)
        let fileResult = removeAudioFile(at: url)
        switch fileResult {
        case .failed:
            return fileResult
        case .deleted, .deletedRecordAudioMissing:
            break
        }
        store.remove(id: memo.id)
        memos = store.allMemos()
        return fileResult
    }

    public func renameMemo(_ memo: VoiceMemo, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.update(id: memo.id) { updated in
            updated.title = trimmed
        }
        memos = store.allMemos()
    }

    public func toggleAutoTranscribe(_ memo: VoiceMemo) {
        store.update(id: memo.id) { updated in
            updated.autoTranscribe.toggle()
            if !updated.autoTranscribe {
                updated.isTranscribing = false
            }
        }
        memos = store.allMemos()

        if let refreshed = memos.first(where: { $0.id == memo.id }),
            refreshed.autoTranscribe,
            refreshed.transcript == nil,
            !refreshed.isTranscribing
        {
            enqueueTranscription(memoID: refreshed.id, fileURL: store.memoURL(for: refreshed))
        }
    }

    public func retranscribe(_ memo: VoiceMemo) {
        guard !memo.isTranscribing else { return }
        store.update(id: memo.id) { updated in
            updated.isTranscribing = true
            updated.transcript = nil
            updated.transcriptWords = nil
        }
        memos = store.allMemos()

        enqueueTranscription(memoID: memo.id, fileURL: store.memoURL(for: memo))
    }

    public func retranscribeMissingTimings() {
        let targets = memos.filter {
            !$0.isTranscribing && ($0.transcriptWords?.isEmpty ?? true)
        }
        guard !targets.isEmpty else { return }

        for memo in targets {
            store.update(id: memo.id) { updated in
                updated.isTranscribing = true
                updated.transcript = nil
                updated.transcriptWords = nil
            }
        }
        memos = store.allMemos()

        for memo in targets {
            enqueueTranscription(memoID: memo.id, fileURL: store.memoURL(for: memo))
        }
    }

    @discardableResult
    public func exportMemo(_ memo: VoiceMemo) -> VoiceMemoExportResult {
#if os(macOS)
        let sourceURL = store.memoURL(for: memo)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        if panel.runModal() == .OK, let destination = panel.url {
            return exportMemo(memo, to: destination)
        }
        return .cancelled
#else
        _ = memo
        return .unsupported
#endif
    }

    @discardableResult
    func exportMemo(_ memo: VoiceMemo, to destination: URL) -> VoiceMemoExportResult {
        let sourceURL = store.memoURL(for: memo)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .sourceAudioMissing(sourceURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return .exported(destination)
        } catch {
            let operationError = VoiceMemoFileOperationError.copyFailed(
                source: sourceURL,
                destination: destination,
                error.localizedDescription
            )
            logger.error("Failed to export memo: \(operationError.localizedDescription, privacy: .public)")
            return .failed(operationError)
        }
    }

    public func audioURL(for memo: VoiceMemo) -> URL {
        store.memoURL(for: memo)
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        currentlyPlayingID = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackTime = 0
        playbackDuration = 0
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: 0.2,
            target: self,
            selector: #selector(updateRecordingMeter),
            userInfo: nil,
            repeats: true
        )
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(updatePlaybackTime),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func updateRecordingMeter() {
        guard let recorder else { return }
        currentDuration = recorder.currentTime
        recorder.updateMeters()
        recordingLevel = normalizedMeterLevel(recorder.averagePower(forChannel: 0))
    }

    @objc private func updatePlaybackTime() {
        guard let player else { return }
        playbackTime = player.currentTime
    }

    private func normalizedMeterLevel(_ power: Float) -> Float {
        let minDb: Float = -50
        let clamped = max(minDb, power)
        return (clamped - minDb) / -minDb
    }

    private func enqueueTranscription(memoID: UUID, fileURL: URL) {
        let job = VoiceMemoTranscriptionQueue.Job(
            memoID: memoID,
            audioFileURL: fileURL,
            settings: settingsStore.load(),
            localeIdentifier: Locale.current.identifier,
            promptProvider: promptProvider
        )
        let previous = transcriptionSubmissionChain
        transcriptionSubmissionChain = Task { @MainActor [weak self] in
            _ = await previous?.value
            guard let self else { return }
            let result = await self.transcriptionQueue.enqueue(job)
            self.applyTranscriptionResult(result, memoID: memoID)
        }
    }

    private func applyTranscriptionResult(
        _ result: Result<MemoTranscriptionResult, VoiceMemoTranscriptionQueueError>,
        memoID: UUID
    ) {
        switch result {
        case .success(let transcription):
            let transcript = transcription.payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            store.update(id: memoID) { memo in
                memo.transcript = transcript.isEmpty ? nil : transcript
                memo.transcriptWords = transcript.isEmpty ? nil : transcription.payload.words
                if transcription.durationSeconds > 0 {
                    memo.durationSeconds = transcription.durationSeconds
                }
                memo.isTranscribing = false
            }
            memos = store.allMemos()
        case .failure(let error):
            logger.error("Memo transcription failed: \(error.localizedDescription, privacy: .public)")
            store.update(id: memoID) { memo in
                memo.isTranscribing = false
                memo.transcript = nil
                memo.transcriptWords = nil
            }
            memos = store.allMemos()
        }
    }

    private func removeAudioFile(at url: URL) -> VoiceMemoDeleteResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .deletedRecordAudioMissing
        }

        do {
            try FileManager.default.removeItem(at: url)
            return .deleted
        } catch {
            let operationError = VoiceMemoFileOperationError.removeFailed(
                url,
                error.localizedDescription
            )
            logger.error("Failed to delete memo audio: \(operationError.localizedDescription, privacy: .public)")
            return .failed(operationError)
        }
    }

    @objc private func handleStoreChange() {
        memos = store.allMemos()
    }

}

@MainActor
extension VoiceMemoManager: AVAudioPlayerDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
        }
    }
}
