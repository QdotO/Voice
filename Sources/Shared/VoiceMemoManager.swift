import AVFoundation
import Foundation
import OSLog
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

public final class VoiceMemoManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var memos: [VoiceMemo] = []
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentDuration: TimeInterval = 0
    @Published public private(set) var currentlyPlayingID: UUID?
    @Published public private(set) var recordingLevel: Float = 0
    @Published public private(set) var playbackTime: TimeInterval = 0
    @Published public private(set) var playbackDuration: TimeInterval = 0

    private let store: VoiceMemoStore
    private let engine: any WhisperEngine
    private let settingsStore: any SettingsStore
    private let promptProvider: @Sendable () async -> String
    private let logger = Logger(subsystem: "Whisper", category: "VoiceMemos")
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var playbackTimer: Timer?
    private var currentMemoID: UUID?
    private var currentFileURL: URL?
    private var transcriptionChain: Task<Void, Never>?

    public init(
        engine: any WhisperEngine,
        settingsStore: any SettingsStore,
        promptProvider: @escaping @Sendable () async -> String,
        store: VoiceMemoStore = .shared
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.promptProvider = promptProvider
        self.store = store
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

    public func deleteMemo(_ memo: VoiceMemo) {
        if currentlyPlayingID == memo.id {
            stopPlayback()
        }

        let url = store.memoURL(for: memo)
        try? FileManager.default.removeItem(at: url)
        store.remove(id: memo.id)
        memos = store.allMemos()
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

    public func exportMemo(_ memo: VoiceMemo) {
#if os(macOS)
        let sourceURL = store.memoURL(for: memo)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        if panel.runModal() == .OK, let destination = panel.url {
            try? FileManager.default.copyItem(at: sourceURL, to: destination)
        }
#else
        _ = memo
#endif
    }

    public func audioURL(for memo: VoiceMemo) -> URL {
        store.memoURL(for: memo)
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPlayback()
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            self.currentDuration = recorder.currentTime
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            self.recordingLevel = normalizedMeterLevel(power)
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            guard let self, let player = self.player else { return }
            self.playbackTime = player.currentTime
        }
    }

    private func normalizedMeterLevel(_ power: Float) -> Float {
        let minDb: Float = -50
        let clamped = max(minDb, power)
        return (clamped - minDb) / -minDb
    }

    private func enqueueTranscription(memoID: UUID, fileURL: URL) {
        let previousTask = transcriptionChain
        transcriptionChain = Task { [weak self] in
            _ = await previousTask?.value
            guard let self else { return }
            await self.transcribe(memoID: memoID, fileURL: fileURL)
        }
    }

    private func transcribe(memoID: UUID, fileURL: URL) async {
        let startedAt = ContinuousClock().now

        do {
            let settings = settingsStore.load()
            let preparation = WhisperEnginePreparation(
                profile: settings.selectedProfile,
                rawModelOverride: settings.rawModelOverride
            )
            try await engine.prepare(preparation)

            let request = MemoTranscriptionRequest(
                memoID: memoID,
                audioFileURL: fileURL,
                profile: settings.selectedProfile,
                localeIdentifier: Locale.current.identifier,
                prompt: await promptProvider()
            )
            let result = try await engine.transcribeMemo(request)
            let transcript = result.payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let elapsed = startedAt.duration(to: ContinuousClock().now)
            let elapsedSeconds = max(0.001, Self.seconds(from: elapsed))
            let throughput = max(0, result.durationSeconds / elapsedSeconds)

            await WhisperTelemetry.shared.record(
                BenchmarkMeasurement(
                    metric: .memoThroughput,
                    value: throughput,
                    unit: .realtimeMultiplier,
                    context: [
                        "memo_id": memoID.uuidString,
                        "characters": "\(transcript.count)",
                    ]
                )
            )

            await MainActor.run {
                self.store.update(id: memoID) { memo in
                    memo.transcript = transcript.isEmpty ? nil : transcript
                    memo.transcriptWords = transcript.isEmpty ? nil : result.payload.words
                    if result.durationSeconds > 0 {
                        memo.durationSeconds = result.durationSeconds
                    }
                    memo.isTranscribing = false
                }
                self.memos = self.store.allMemos()
            }
        } catch {
            logger.error("Memo transcription failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                self.store.update(id: memoID) { memo in
                    memo.isTranscribing = false
                    memo.transcript = nil
                    memo.transcriptWords = nil
                }
                self.memos = self.store.allMemos()
            }
        }
    }

    @objc private func handleStoreChange() {
        memos = store.allMemos()
    }

    private static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
