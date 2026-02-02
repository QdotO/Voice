import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers

final class VoiceMemoManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var memos: [VoiceMemo] = []
    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var currentlyPlayingID: UUID?
    @Published private(set) var recordingLevel: Float = 0
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var playbackDuration: TimeInterval = 0

    private let store: VoiceMemoStore
    private let transcriber: Transcriber
    private let modelProvider: () -> String
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var playbackTimer: Timer?
    private var currentMemoID: UUID?
    private var currentFileURL: URL?

    init(
        transcriber: Transcriber,
        modelProvider: @escaping () -> String,
        store: VoiceMemoStore = .shared
    ) {
        self.transcriber = transcriber
        self.modelProvider = modelProvider
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

    func startRecording() {
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
            print("[VoiceMemo] Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
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
            Task {
                await transcribe(memoID: memoID, fileURL: fileURL)
            }
        } else {
            store.update(id: memoID) { updated in
                updated.isTranscribing = false
            }
            memos = store.allMemos()
        }
    }

    func togglePlayback(for memo: VoiceMemo) {
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
            print("[VoiceMemo] Failed to play memo: \(error)")
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, player.duration))
        player.currentTime = clamped
        playbackTime = clamped
    }

    func deleteMemo(_ memo: VoiceMemo) {
        if currentlyPlayingID == memo.id {
            stopPlayback()
        }

        let url = store.memoURL(for: memo)
        try? FileManager.default.removeItem(at: url)
        store.remove(id: memo.id)
        memos = store.allMemos()
    }

    func renameMemo(_ memo: VoiceMemo, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.update(id: memo.id) { updated in
            updated.title = trimmed
        }
        memos = store.allMemos()
    }

    func toggleAutoTranscribe(_ memo: VoiceMemo) {
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
            Task {
                await transcribe(memoID: refreshed.id, fileURL: store.memoURL(for: refreshed))
            }
        }
    }

    func retranscribe(_ memo: VoiceMemo) {
        guard !memo.isTranscribing else { return }
        store.update(id: memo.id) { updated in
            updated.isTranscribing = true
            updated.transcript = nil
            updated.transcriptWords = nil
        }
        memos = store.allMemos()

        Task {
            await transcribe(memoID: memo.id, fileURL: store.memoURL(for: memo))
        }
    }

    func retranscribeMissingTimings() {
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

        Task {
            for memo in targets {
                await transcribe(memoID: memo.id, fileURL: store.memoURL(for: memo))
            }
        }
    }

    func exportMemo(_ memo: VoiceMemo) {
        let sourceURL = store.memoURL(for: memo)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        if panel.runModal() == .OK, let destination = panel.url {
            try? FileManager.default.copyItem(at: sourceURL, to: destination)
        }
    }

    func audioURL(for memo: VoiceMemo) -> URL {
        store.memoURL(for: memo)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
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

    private func transcribe(memoID: UUID, fileURL: URL) async {
        do {
            let model = modelProvider()
            if transcriber.modelName != model {
                await transcriber.loadModel(model)
            }

            let audio = try AudioFileLoader.loadPCM16kMono(from: fileURL)
            guard let payload = await transcriber.transcribe(audio) else {
                store.update(id: memoID) { memo in
                    memo.isTranscribing = false
                    memo.transcript = nil
                    memo.transcriptWords = nil
                }
                memos = store.allMemos()
                return
            }

            store.update(id: memoID) { memo in
                memo.transcript = payload.text
                memo.transcriptWords = payload.words
                memo.isTranscribing = false
            }
            memos = store.allMemos()
        } catch {
            print("[VoiceMemo] Transcription failed: \(error)")
            store.update(id: memoID) { memo in
                memo.isTranscribing = false
                memo.transcript = nil
                memo.transcriptWords = nil
            }
            memos = store.allMemos()
        }
    }

    @objc private func handleStoreChange() {
        memos = store.allMemos()
    }
}
