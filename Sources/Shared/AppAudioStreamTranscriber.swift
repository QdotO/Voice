// Adapted from WhisperKit 0.15 AudioStreamTranscriber lifecycle.
// Copyright © 2024 Argmax, Inc. Used here to keep app-owned permission and
// cancellation semantics without modifying the package checkout.

import Foundation
import WhisperKit

/// App-owned live stream adapter. Permission is intentionally absent: caller
/// must complete permission before invoking `startStreamTranscription()`.
actor AppAudioStreamTranscriber {
    struct State {
        var isRecording = false
        var currentFallbacks = 0
        var lastBufferSize = 0
        var lastConfirmedSegmentEndSeconds: Float = 0
        var bufferEnergy: [Float] = []
        var currentText = ""
        var confirmedSegments: [TranscriptionSegment] = []
        var unconfirmedSegments: [TranscriptionSegment] = []
        var unconfirmedText: [String] = []
    }

    typealias StateChangeCallback = (State, State) -> Void

    private var state = State() {
        didSet { stateChangeCallback?(oldValue, state) }
    }

    private let stateChangeCallback: StateChangeCallback?
    private let requiredSegmentsForConfirmation: Int
    private let useVAD: Bool
    private let silenceThreshold: Float
    private let compressionCheckWindow: Int
    private let transcribeTask: TranscribeTask
    private let audioProcessor: any AudioProcessing
    private let decodingOptions: DecodingOptions
    private var captureGate = AppOwnedCaptureGate()

    init(
        audioEncoder: any AudioEncoding,
        featureExtractor: any FeatureExtracting,
        segmentSeeker: any SegmentSeeking,
        textDecoder: any TextDecoding,
        tokenizer: any WhisperTokenizer,
        audioProcessor: any AudioProcessing,
        decodingOptions: DecodingOptions,
        requiredSegmentsForConfirmation: Int = 2,
        silenceThreshold: Float = 0.3,
        compressionCheckWindow: Int = 60,
        useVAD: Bool = true,
        stateChangeCallback: StateChangeCallback?
    ) {
        self.transcribeTask = TranscribeTask(
            currentTimings: TranscriptionTimings(),
            progress: Progress(),
            audioProcessor: audioProcessor,
            audioEncoder: audioEncoder,
            featureExtractor: featureExtractor,
            segmentSeeker: segmentSeeker,
            textDecoder: textDecoder,
            tokenizer: tokenizer
        )
        self.audioProcessor = audioProcessor
        self.decodingOptions = decodingOptions
        self.requiredSegmentsForConfirmation = requiredSegmentsForConfirmation
        self.silenceThreshold = silenceThreshold
        self.compressionCheckWindow = compressionCheckWindow
        self.useVAD = useVAD
        self.stateChangeCallback = stateChangeCallback
    }

    func startStreamTranscription() async throws {
        guard !state.isRecording, captureGate.beginCapture() else { return }
        try Task.checkCancellation()

        // Actor isolation holds through this synchronous call. A stop either
        // wins before it, or stops capture after it; start cannot revive it.
        try audioProcessor.startRecordingLive { [weak self] _ in
            Task { await self?.onAudioBufferCallback() }
        }
        guard !captureGate.stopRequested else {
            audioProcessor.stopRecording()
            return
        }

        state.isRecording = true
        do {
            try await realtimeLoop()
        } catch {
            stopCapture()
            throw error
        }
    }

    func stopStreamTranscription() {
        guard captureGate.stop() else { return }
        stopCapture()
    }

    func didBeginCapture() -> Bool {
        captureGate.didBeginCapture
    }

    private func stopCapture() {
        if state.isRecording {
            state.isRecording = false
        }
        audioProcessor.stopRecording()
    }

    private func realtimeLoop() async throws {
        while state.isRecording, !captureGate.stopRequested {
            try await transcribeCurrentBuffer()
        }
    }

    private func onAudioBufferCallback() {
        guard !captureGate.stopRequested else { return }
        state.bufferEnergy = audioProcessor.relativeEnergy
    }

    private func onProgressCallback(_ progress: TranscriptionProgress) {
        guard !captureGate.stopRequested else { return }
        let fallbacks = Int(progress.timings.totalDecodingFallbacks)
        if progress.text.count < state.currentText.count, fallbacks == state.currentFallbacks {
            state.unconfirmedText.append(state.currentText)
        }
        state.currentText = progress.text
        state.currentFallbacks = fallbacks
    }

    private func transcribeCurrentBuffer() async throws {
        let currentBuffer = audioProcessor.audioSamples
        let nextBufferSize = currentBuffer.count - state.lastBufferSize
        let nextBufferSeconds = Float(nextBufferSize) / Float(WhisperKit.sampleRate)

        guard nextBufferSeconds > 1 else {
            if state.currentText.isEmpty {
                state.currentText = "Waiting for speech..."
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            return
        }

        if useVAD {
            let voiceDetected = AudioProcessor.isVoiceDetected(
                in: audioProcessor.relativeEnergy,
                nextBufferInSeconds: nextBufferSeconds,
                silenceThreshold: silenceThreshold
            )
            guard voiceDetected else {
                if state.currentText.isEmpty {
                    state.currentText = "Waiting for speech..."
                }
                try await Task.sleep(nanoseconds: 100_000_000)
                return
            }
        }

        state.lastBufferSize = currentBuffer.count
        let transcription = try await transcribeAudioSamples(Array(currentBuffer))

        state.currentText = ""
        state.unconfirmedText = []
        let segments = transcription.segments
        if segments.count > requiredSegmentsForConfirmation {
            let confirmedSegments = Array(segments.dropLast(requiredSegmentsForConfirmation))
            if let lastConfirmed = confirmedSegments.last,
               lastConfirmed.end > state.lastConfirmedSegmentEndSeconds {
                state.lastConfirmedSegmentEndSeconds = lastConfirmed.end
                if !state.confirmedSegments.contains(confirmedSegments) {
                    state.confirmedSegments.append(contentsOf: confirmedSegments)
                }
            }
            state.unconfirmedSegments = Array(segments.suffix(requiredSegmentsForConfirmation))
        } else {
            state.unconfirmedSegments = segments
        }
    }

    private func transcribeAudioSamples(_ samples: [Float]) async throws -> TranscriptionResult {
        var options = decodingOptions
        options.clipTimestamps = [state.lastConfirmedSegmentEndSeconds]
        let checkWindow = compressionCheckWindow
        return try await transcribeTask.run(audioArray: samples, decodeOptions: options) { [weak self] progress in
            Task { await self?.onProgressCallback(progress) }
            return Self.shouldStopEarly(
                progress: progress,
                options: options,
                compressionCheckWindow: checkWindow
            )
        }
    }

    private static func shouldStopEarly(
        progress: TranscriptionProgress,
        options: DecodingOptions,
        compressionCheckWindow: Int
    ) -> Bool? {
        if progress.tokens.count > compressionCheckWindow {
            let tokens = progress.tokens.suffix(compressionCheckWindow)
            if TextUtilities.compressionRatio(of: Array(tokens)) > options.compressionRatioThreshold ?? 0 {
                return false
            }
        }
        if let average = progress.avgLogprob,
           let threshold = options.logProbThreshold,
           average < threshold {
            return false
        }
        return nil
    }
}
