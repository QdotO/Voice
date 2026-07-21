import AVFoundation
import Foundation
import OSLog
import WhisperKit

public enum WhisperEngineRuntimeError: LocalizedError, Sendable {
    case dictationAlreadyRunning
    case tokenizerUnavailable
    case engineUnavailable
    case microphonePermissionDenied
    case streamEndedUnexpectedly

    public var errorDescription: String? {
        switch self {
        case .dictationAlreadyRunning:
            return "A dictation session is already running."
        case .tokenizerUnavailable:
            return "Whisper tokenizer is unavailable."
        case .engineUnavailable:
            return "Whisper engine is unavailable."
        case .microphonePermissionDenied:
            return "Microphone permission was denied."
        case .streamEndedUnexpectedly:
            return "Live transcription stopped unexpectedly."
        }
    }
}

public actor LiveWhisperEngine: WhisperEngine {
    private struct StreamSnapshot: Equatable, Sendable {
        var transcript: String = ""
        var words: [TranscriptWord] = []
        var audioLevel: Float = 0
        var lastBufferSize: Int = 0
        var revision: UInt64 = 0
    }

    private struct ActiveStreamSession {
        let sessionID: UUID
        let continuation: DictationUpdateStream.Continuation
        var transcriber: AppAudioStreamTranscriber?
        var task: Task<Void, Never>?
        var finalDecodeOptions: DecodingOptions?
        var lifecycle = LiveDictationSessionLifecycle()
        var lastSnapshot: StreamSnapshot = .init()
        var didEmitRecording = false
        var lastPartialTranscript = ""
    }

    private let logger = Logger(subsystem: "Whisper", category: "V2Engine")
    private let audioLevelHandler: (@Sendable (Float) -> Void)?

    private var whisperKit: WhisperKit?
    private var preparedRequest: WhisperEnginePreparation?
    private var activeStream: ActiveStreamSession?
    private var stoppingTasks: [UUID: Task<Void, Never>] = [:]
    private let permissionRequester: @Sendable () async -> Bool

    public init(
        audioLevelHandler: (@Sendable (Float) -> Void)? = nil,
        permissionRequester: @escaping @Sendable () async -> Bool = { await AudioProcessor.requestRecordPermission() }
    ) {
        self.audioLevelHandler = audioLevelHandler
        self.permissionRequester = permissionRequester
    }

    public func prepareMicrophoneAccess() async throws {
        guard await permissionRequester() else {
            throw WhisperEngineRuntimeError.microphonePermissionDenied
        }
    }

    public func prepare(_ request: WhisperEnginePreparation) async throws {
        if let preparedRequest, preparedRequest == request, whisperKit != nil {
            return
        }

        if activeStream != nil {
            await stopDictation(sessionID: activeStream?.sessionID ?? UUID())
        }

        try await loadWhisperKit(for: request)
    }

    private func loadWhisperKit(for request: WhisperEnginePreparation) async throws {
        let resolvedModelName = request.resolvedModelName

        logger.info("Preparing WhisperKit with model \(resolvedModelName, privacy: .public)")

        let config = WhisperKitConfig(
            model: resolvedModelName,
            voiceActivityDetector: EnergyVAD(),
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: true
        )

        let whisperKit = try await WhisperKit(config)
        self.whisperKit = whisperKit
        self.preparedRequest = request
    }

    public func startDictation(_ request: DictationSessionRequest) async throws -> DictationUpdateStream {
        if activeStream != nil {
            throw WhisperEngineRuntimeError.dictationAlreadyRunning
        }

        var continuation: DictationUpdateStream.Continuation?
        let stream = AsyncThrowingStream<DictationSessionUpdate, Error> { localContinuation in
            continuation = localContinuation
            localContinuation.onTermination = { _ in
                Task { await self.handleStreamTermination(sessionID: request.sessionID) }
            }
        }
        guard let continuation else {
            throw WhisperEngineRuntimeError.engineUnavailable
        }

        // Reserve before preparation or microphone permission. Stop and
        // prepare calls now see this session rather than racing its startup.
        activeStream = ActiveStreamSession(
            sessionID: request.sessionID,
            continuation: continuation
        )
        continuation.yield(DictationSessionUpdate(sessionID: request.sessionID, state: .preparing))

        do {
            try await ensurePrepared(for: request.profile)
        } catch {
            finishStream(sessionID: request.sessionID, error: error)
            throw error
        }

        guard var activeStream, activeStream.sessionID == request.sessionID,
              activeStream.lifecycle.phase == .starting else {
            return stream
        }
        guard let whisperKit else {
            let error = WhisperEngineRuntimeError.engineUnavailable
            finishStream(sessionID: request.sessionID, error: error)
            throw error
        }
        guard let tokenizer = whisperKit.tokenizer else {
            let error = WhisperEngineRuntimeError.tokenizerUnavailable
            finishStream(sessionID: request.sessionID, error: error)
            throw error
        }

        let decodeOptions = makeStreamingDecodingOptions(
            prompt: request.prompt,
            tokenizer: tokenizer,
            localeIdentifier: request.localeIdentifier,
            modelName: preparedRequest?.resolvedModelName ?? request.profile.defaultModelName
        )

        let transcriber = AppAudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisperKit.audioProcessor,
            decodingOptions: decodeOptions,
            requiredSegmentsForConfirmation: 2,
            silenceThreshold: 0.3,
            compressionCheckWindow: 60,
            // Keep live dictation permissive; VAD gating is used for memo/long-form paths.
            useVAD: false,
            stateChangeCallback: { [weak self] oldState, newState, revision in
                let recordingStarted = !oldState.isRecording && newState.isRecording
                let snapshot = Self.makeSnapshot(from: newState, revision: revision)
                Task {
                    await self?.handleStreamStateChange(
                        sessionID: request.sessionID,
                        recordingStarted: recordingStarted,
                        snapshot: snapshot
                    )
                }
            }
        )

        activeStream.transcriber = transcriber
        activeStream.finalDecodeOptions = decodeOptions
        self.activeStream = activeStream

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runStream(sessionID: request.sessionID, transcriber: transcriber)
        }
        guard var session = self.activeStream, session.sessionID == request.sessionID else {
            task.cancel()
            return stream
        }
        session.task = task
        self.activeStream = session

        return stream
    }

    private func runStream(sessionID: UUID, transcriber: AppAudioStreamTranscriber) async {
        do {
            guard await permissionRequester() else {
                throw WhisperEngineRuntimeError.microphonePermissionDenied
            }
            guard beginStreamLaunch(sessionID: sessionID) else { return }
            try Task.checkCancellation()
            guard beginTranscriberStart(sessionID: sessionID) else { return }

            logStreamEvent("Starting audio stream session=\(sessionID.uuidString)")
            try await transcriber.startStreamTranscription()

            // Local adapter rethrows realtime decode failures after stopping
            // capture. A normal return outside our stop path is unexpected.
            whisperKit?.audioProcessor.stopRecording()
            finishStream(sessionID: sessionID, error: WhisperEngineRuntimeError.streamEndedUnexpectedly)
        } catch {
            whisperKit?.audioProcessor.stopRecording()
            logStreamEvent(
                "Audio stream failed session=\(sessionID.uuidString) error=\(error.localizedDescription)"
            )
            finishStream(sessionID: sessionID, error: error)
        }
    }

    private func beginStreamLaunch(sessionID: UUID) -> Bool {
        guard var activeStream, activeStream.sessionID == sessionID else { return false }
        guard activeStream.lifecycle.beginLaunch() else { return false }
        self.activeStream = activeStream
        return true
    }

    private func beginTranscriberStart(sessionID: UUID) -> Bool {
        guard var activeStream, activeStream.sessionID == sessionID else { return false }
        guard activeStream.lifecycle.beginTranscriberStart() else { return false }
        self.activeStream = activeStream
        return true
    }

    public func stopDictation(sessionID: UUID) async {
        if let stoppingTask = stoppingTasks[sessionID] {
            await stoppingTask.value
            return
        }
        guard let activeStream, activeStream.sessionID == sessionID else { return }

        let stoppingTask = Task { [weak self] in
            guard let self else { return }
            await self.performStopDictation(sessionID: sessionID)
        }
        stoppingTasks[sessionID] = stoppingTask
        await stoppingTask.value
        stoppingTasks[sessionID] = nil
    }

    private func performStopDictation(sessionID: UUID) async {
        guard var activeStream, activeStream.sessionID == sessionID else { return }
        let transcriberNeedsCleanup = activeStream.lifecycle.needsTranscriberCleanup
        var didBeginCapture = activeStream.lifecycle.hasStartedCapture
        guard activeStream.lifecycle.beginStopping() else { return }
        self.activeStream = activeStream
        logger.info(
            "Stopping stream session=\(sessionID.uuidString, privacy: .public) lastDecodedSamples=\(activeStream.lastSnapshot.lastBufferSize, privacy: .public)"
        )

        // Always stop hardware ourselves. This covers WhisperKit's normal
        // return after a swallowed decode error and startup cancellation.
        whisperKit?.audioProcessor.stopRecording()
        if transcriberNeedsCleanup, let transcriber = activeStream.transcriber {
            await transcriber.stopStreamTranscription()
            didBeginCapture = await transcriber.didBeginCapture()
        }

        // Permission can remain pending indefinitely. Never await that task
        // during stop; phase check in runStream prevents later capture start.
        if transcriberNeedsCleanup, let task = activeStream.task {
            await task.value
        } else {
            activeStream.task?.cancel()
        }
        logger.info(
            "Audio stream stopped session=\(sessionID.uuidString, privacy: .public)"
        )

        // Live decoding requires more than one second of new audio. Stopping
        // can leave a sub-second tail untouched, so decode only residual tail
        // plus bounded context with end clipping disabled.
        var flushedSnapshot: StreamSnapshot?
        if didBeginCapture {
            do {
                flushedSnapshot = try await flushFinalAudio(
                    using: activeStream.finalDecodeOptions,
                    lastDecodedSamples: activeStream.lastSnapshot.lastBufferSize
                )
            } catch {
                finishStoppedStreamWithError(sessionID: sessionID, error: error)
                return
            }
        } else {
            logger.info("Final stream flush skipped: capture never began")
        }

        guard var finalStream = self.activeStream, finalStream.sessionID == sessionID else { return }
        if let flushedSnapshot {
            let merged = FinalTailTranscriptMerger.merge(
                currentText: finalStream.lastSnapshot.transcript,
                currentWords: finalStream.lastSnapshot.words,
                tailText: flushedSnapshot.transcript,
                tailWords: flushedSnapshot.words,
                decodedThroughSeconds: Double(finalStream.lastSnapshot.lastBufferSize) / Double(WhisperKit.sampleRate)
            )
            finalStream.lastSnapshot.transcript = merged.text
            finalStream.lastSnapshot.words = merged.words
            finalStream.lastSnapshot.lastBufferSize = max(
                finalStream.lastSnapshot.lastBufferSize,
                flushedSnapshot.lastBufferSize
            )
            self.activeStream = finalStream
        }

        guard let finalStream = self.activeStream, finalStream.sessionID == sessionID else { return }
        let finalTranscript = finalStream.lastSnapshot.transcript
        let finalWords = finalStream.lastSnapshot.words

        audioLevelHandler?(0)

        if !finalTranscript.isEmpty, finalStream.lastPartialTranscript != finalTranscript {
            finalStream.continuation.yield(
                DictationSessionUpdate(
                    sessionID: sessionID,
                    state: .partial,
                    transcript: finalTranscript,
                    words: finalWords
                ))
        }

        finalStream.continuation.yield(
            DictationSessionUpdate(
                sessionID: sessionID,
                state: .finalizing,
                transcript: finalTranscript,
                words: finalWords
            ))
        finalStream.continuation.yield(
            DictationSessionUpdate(
                sessionID: sessionID,
                state: .completed,
                transcript: finalTranscript,
                words: finalWords
            ))
        finalStream.continuation.finish()

        self.activeStream = nil
    }

    private func flushFinalAudio(
        using decodeOptions: DecodingOptions?,
        lastDecodedSamples: Int
    ) async throws -> StreamSnapshot? {
        guard let whisperKit else { return nil }
        guard let decodeOptions else { return nil }

        let audioSamples = Array(whisperKit.audioProcessor.audioSamples)
        guard let window = BoundedFinalAudioWindow.make(
            totalSamples: audioSamples.count,
            lastDecodedSamples: lastDecodedSamples,
            sampleRate: WhisperKit.sampleRate
        ) else {
            logger.info("Final stream flush skipped: no undecoded audio")
            return nil
        }

        let windowSamples = Array(audioSamples[window.range])
        let offsetSeconds = Double(window.range.lowerBound) / Double(WhisperKit.sampleRate)

        logger.info(
            "Final stream flush starting samples=\(windowSamples.count, privacy: .public) offset=\(offsetSeconds, privacy: .public)s"
        )

        var finalOptions = decodeOptions
        finalOptions.clipTimestamps = []
        finalOptions.windowClipTime = 0

        let results = try await whisperKit.transcribe(
            audioArray: windowSamples,
            decodeOptions: finalOptions
        )
        guard !results.isEmpty else { return nil }

        let merged = TranscriptionUtilities.mergeTranscriptionResults(results.map(Optional.some))
        logger.info(
            "Final stream flush finished results=\(results.count, privacy: .public) chars=\(merged.text.count, privacy: .public)"
        )
        return StreamSnapshot(
            transcript: Self.cleanTranscription(merged.text),
            words: Self.mapWords(from: merged.allWords, offsetSeconds: offsetSeconds),
            lastBufferSize: audioSamples.count
        )
    }

    private func finishStoppedStreamWithError(sessionID: UUID, error: Error) {
        guard let activeStream, activeStream.sessionID == sessionID else { return }

        logger.error(
            "Final stream flush failed session=\(sessionID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
        )
        audioLevelHandler?(0)
        activeStream.continuation.yield(
            DictationSessionUpdate(
                sessionID: sessionID,
                state: .failed,
                transcript: activeStream.lastSnapshot.transcript,
                words: activeStream.lastSnapshot.words,
                errorDescription: error.localizedDescription
            ))
        activeStream.continuation.finish(throwing: error)
        self.activeStream = nil
    }

    public func transcribeMemo(_ request: MemoTranscriptionRequest) async throws -> MemoTranscriptionResult {
        try await ensurePrepared(for: request.profile)
        guard let whisperKit else {
            throw WhisperEngineRuntimeError.engineUnavailable
        }
        guard let tokenizer = whisperKit.tokenizer else {
            throw WhisperEngineRuntimeError.tokenizerUnavailable
        }

        let decodeOptions = makeMemoDecodingOptions(
            prompt: request.prompt,
            tokenizer: tokenizer,
            localeIdentifier: request.localeIdentifier,
            modelName: preparedRequest?.resolvedModelName ?? request.profile.defaultModelName
        )

        let results = try await whisperKit.transcribe(
            audioPath: request.audioFileURL.path,
            decodeOptions: decodeOptions
        )
        let merged = TranscriptionUtilities.mergeTranscriptionResults(results.map(Optional.some))
        let cleanedText = Self.cleanTranscription(merged.text)
        let payload = TranscriptionPayload(
            text: cleanedText,
            words: Self.mapWords(from: merged.allWords)
        )

        return MemoTranscriptionResult(
            memoID: request.memoID,
            payload: payload,
            durationSeconds: audioDuration(for: request.audioFileURL)
        )
    }

    private func ensurePrepared(for profile: ModelProfile) async throws {
        if whisperKit != nil, preparedRequest?.profile == profile {
            return
        }
        try await loadWhisperKit(for: WhisperEnginePreparation(profile: profile))
    }

    private func finishStream(sessionID: UUID, error: Error?) {
        guard let activeStream, activeStream.sessionID == sessionID else { return }
        if activeStream.lifecycle.isStopping {
            return
        }

        if let error {
            logger.error(
                "Finishing stream with error session=\(sessionID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        } else {
            logger.info(
                "Finishing stream normally session=\(sessionID.uuidString, privacy: .public) chars=\(activeStream.lastSnapshot.transcript.count, privacy: .public) lastDecodedSamples=\(activeStream.lastSnapshot.lastBufferSize, privacy: .public)"
            )
        }

        if let error {
            audioLevelHandler?(0)
            activeStream.continuation.yield(
                DictationSessionUpdate(
                    sessionID: sessionID,
                    state: .failed,
                    transcript: activeStream.lastSnapshot.transcript,
                    words: activeStream.lastSnapshot.words,
                    errorDescription: error.localizedDescription
                ))
            activeStream.continuation.finish(throwing: error)
        } else {
            audioLevelHandler?(0)
            activeStream.continuation.yield(
                DictationSessionUpdate(
                    sessionID: sessionID,
                    state: .completed,
                    transcript: activeStream.lastSnapshot.transcript,
                    words: activeStream.lastSnapshot.words
                ))
            activeStream.continuation.finish()
        }

        self.activeStream = nil
    }

    private func handleStreamTermination(sessionID: UUID) async {
        await stopDictation(sessionID: sessionID)
    }

    private func handleStreamStateChange(
        sessionID: UUID,
        recordingStarted: Bool,
        snapshot: StreamSnapshot
    ) async {
        guard var activeStream, activeStream.sessionID == sessionID else { return }
        if recordingStarted {
            logger.info(
                "Audio recording started session=\(sessionID.uuidString, privacy: .public)"
            )
            if activeStream.lifecycle.recordingBegan() {
                self.activeStream = activeStream
                whisperKit?.audioProcessor.stopRecording()
                if let transcriber = activeStream.transcriber {
                    await transcriber.stopStreamTranscription()
                }
                return
            }
        }
        if snapshot.lastBufferSize > activeStream.lastSnapshot.lastBufferSize {
            logger.debug(
                "Stream decode scheduled session=\(sessionID.uuidString, privacy: .public) samples=\(snapshot.lastBufferSize, privacy: .public)"
            )
        }
        if LiveSnapshotProgress.shouldReplaceText(
            currentRevision: activeStream.lastSnapshot.revision,
            candidateRevision: snapshot.revision,
            currentSampleCount: activeStream.lastSnapshot.lastBufferSize,
            candidateSampleCount: snapshot.lastBufferSize,
            currentWordEnd: activeStream.lastSnapshot.words.last?.end ?? 0,
            candidateWordEnd: snapshot.words.last?.end ?? 0,
            candidateText: snapshot.transcript
        ) {
            activeStream.lastSnapshot = snapshot
        } else {
            // Preserve last nonempty decoded text while keeping progress current.
            activeStream.lastSnapshot.audioLevel = snapshot.audioLevel
            activeStream.lastSnapshot.lastBufferSize = max(
                activeStream.lastSnapshot.lastBufferSize,
                snapshot.lastBufferSize
            )
            activeStream.lastSnapshot.revision = max(
                activeStream.lastSnapshot.revision,
                snapshot.revision
            )
        }
        audioLevelHandler?(snapshot.audioLevel)

        if recordingStarted && !activeStream.didEmitRecording {
            activeStream.didEmitRecording = true
            activeStream.continuation.yield(
                DictationSessionUpdate(sessionID: sessionID, state: .recording)
            )
        }

        let partialTranscript = activeStream.lastSnapshot.transcript
        if !partialTranscript.isEmpty, partialTranscript != activeStream.lastPartialTranscript {
            activeStream.lastPartialTranscript = partialTranscript
            activeStream.continuation.yield(
                DictationSessionUpdate(
                    sessionID: sessionID,
                    state: .partial,
                    transcript: partialTranscript,
                    words: activeStream.lastSnapshot.words
                ))
        }

        self.activeStream = activeStream
    }

    private func makeStreamingDecodingOptions(
        prompt: String,
        tokenizer: any WhisperTokenizer,
        localeIdentifier: String,
        modelName: String
    ) -> DecodingOptions {
        var options = baseDecodingOptions(
            prompt: prompt,
            tokenizer: tokenizer,
            localeIdentifier: localeIdentifier,
            modelName: modelName
        )
        // Prevent prompt token leakage in live dictation output.
        options.usePrefillPrompt = false
        options.usePrefillCache = false
        options.promptTokens = nil
        options.chunkingStrategy = ChunkingStrategy.none
        return options
    }

    private func makeMemoDecodingOptions(
        prompt: String,
        tokenizer: any WhisperTokenizer,
        localeIdentifier: String,
        modelName: String
    ) -> DecodingOptions {
        var options = baseDecodingOptions(
            prompt: prompt,
            tokenizer: tokenizer,
            localeIdentifier: localeIdentifier,
            modelName: modelName
        )
        options.chunkingStrategy = .vad
        return options
    }

    private func baseDecodingOptions(
        prompt: String,
        tokenizer: any WhisperTokenizer,
        localeIdentifier: String,
        modelName: String
    ) -> DecodingOptions {
        var options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: Self.languageCode(localeIdentifier: localeIdentifier, modelName: modelName),
            temperature: 0.0,
            temperatureFallbackCount: 3,
            topK: 5,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            suppressBlank: false,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.3,
            concurrentWorkerCount: 4
        )

        let promptTokens = Self.promptTokens(from: prompt, tokenizer: tokenizer)
        if !promptTokens.isEmpty {
            options.promptTokens = promptTokens
        }

        return options
    }

    private nonisolated static func promptTokens(
        from prompt: String,
        tokenizer: any WhisperTokenizer
    ) -> [Int] {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return tokenizer.encode(text: trimmed)
    }

    private nonisolated static func languageCode(localeIdentifier: String, modelName: String) -> String? {
        if modelName.hasSuffix(".en") {
            return "en"
        }

        let normalized = localeIdentifier.replacingOccurrences(of: "-", with: "_")
        let language = normalized.split(separator: "_").first.map(String.init)
        return language?.isEmpty == false ? language : nil
    }

    private nonisolated static func makeSnapshot(
        from state: AppAudioStreamTranscriber.State,
        revision: UInt64
    ) -> StreamSnapshot {
        let confirmedText = state.confirmedSegments.map(\.text).joined()
        let unconfirmedText: String
        if !state.unconfirmedSegments.isEmpty {
            unconfirmedText = state.unconfirmedSegments.map(\.text).joined()
        } else if state.currentText == "Waiting for speech..." {
            unconfirmedText = ""
        } else {
            unconfirmedText = state.currentText
        }

        let transcript = cleanTranscription(confirmedText + unconfirmedText)
        let words = mapWords(
            from: state.confirmedSegments.compactMap(\.words).flatMap { $0 }
                + state.unconfirmedSegments.compactMap(\.words).flatMap { $0 }
        )
        let recentEnergy = state.bufferEnergy.suffix(6)
        let audioLevel = recentEnergy.isEmpty ? 0 : recentEnergy.reduce(0, +) / Float(recentEnergy.count)

        return StreamSnapshot(
            transcript: transcript,
            words: words,
            audioLevel: audioLevel,
            lastBufferSize: state.lastBufferSize,
            revision: revision
        )
    }

    private nonisolated static func moreCompleteSnapshot(
        _ current: StreamSnapshot,
        _ candidate: StreamSnapshot
    ) -> StreamSnapshot {
        let transcript = StreamingTranscriptAccumulator.moreComplete(
            current.transcript,
            candidate.transcript
        )

        if transcript == candidate.transcript {
            return candidate
        }

        var preserved = current
        preserved.audioLevel = candidate.audioLevel
        preserved.lastBufferSize = candidate.lastBufferSize
        return preserved
    }

    private func logStreamEvent(_ message: String) {
        logger.info("\(message)")
    }

    private nonisolated static func mapWords(
        from words: [WordTiming],
        offsetSeconds: Double = 0
    ) -> [TranscriptWord] {
        words
            .map { word in
                TranscriptWord(
                    word: word.word.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: Double(word.start) + offsetSeconds,
                    end: Double(word.end) + offsetSeconds
                )
            }
            .filter { !$0.word.isEmpty }
    }

    private nonisolated static func cleanTranscription(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let fullArtifacts = [
            "[BLANK_AUDIO]",
            "[MUSIC]",
            "[APPLAUSE]",
            "(music)",
            "(applause)",
            "Thank you.",
            "Thanks for watching.",
            "Please subscribe.",
        ]

        if fullArtifacts.contains(where: { cleaned.lowercased() == $0.lowercased() }) {
            return ""
        }

        let inlineArtifacts = ["[BLANK_AUDIO]", "[MUSIC]", "[APPLAUSE]", "..."]
        for artifact in inlineArtifacts {
            cleaned = cleaned.replacingOccurrences(of: artifact, with: "")
        }

        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func audioDuration(for url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else {
            return 0
        }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
