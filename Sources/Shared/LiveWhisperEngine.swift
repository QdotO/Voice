import AVFoundation
import Foundation
import OSLog

// WhisperKit 0.9 exposes its model and pipeline protocols without Sendable
// annotations. This engine owns one model instance and keeps its lifecycle in
// this actor. Live inference owns pipeline access until stream completion;
// memo/final-tail inference waits for that completion and then uses one
// serialized queue. No WhisperKit reference is used concurrently. Preconcurrency
// import limits this boundary to third-party declarations; it does not claim
// WhisperKit is globally Sendable.
@preconcurrency import WhisperKit

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

/// Internal seams keep model lifecycle tests deterministic without exposing
/// WhisperKit details through the public engine API.
protocol LiveWhisperModelLoader: Sendable {
    func loadModel(for request: WhisperEnginePreparation) async throws -> WhisperKit
}

protocol LiveWhisperInference: Sendable {
    func transcribe(
        model: WhisperKit,
        audioPath: String,
        decodeOptions: DecodingOptions
    ) async throws -> [TranscriptionResult]

    func transcribe(
        model: WhisperKit,
        audioSamples: [Float],
        decodeOptions: DecodingOptions
    ) async throws -> [TranscriptionResult]
}

/// Test seam for final-tail policy. Production finalization uses the same
/// resolution path with real inference results and errors.
enum FinalTailTestDecodeOutcome: Sendable {
    case success
    case noResult
    case failure
    case canceled
}

struct FinalTailTestResolution: Equatable, Sendable {
    let transcript: String
    let words: [TranscriptWord]
    let usedLiveSnapshotFallback: Bool
}

private final class PreparationWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<WhisperKit, Error>?
    private var didFinish = false
    private var didCancel = false

    func install(_ continuation: CheckedContinuation<WhisperKit, Error>) {
        let shouldCancel: Bool
        lock.lock()
        shouldCancel = didCancel || didFinish
        if !shouldCancel {
            self.continuation = continuation
        }
        lock.unlock()

        if shouldCancel {
            continuation.resume(throwing: CancellationError())
        }
    }

    func cancel() {
        let continuation: CheckedContinuation<WhisperKit, Error>?
        lock.lock()
        didCancel = true
        continuation = self.continuation
        self.continuation = nil
        didFinish = true
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }

    func complete(_ result: Result<WhisperKit, Error>) {
        let continuation: CheckedContinuation<WhisperKit, Error>?
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        switch result {
        case let .success(model):
            continuation?.resume(returning: model)
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
    }
}

private final class PreparationObservation: @unchecked Sendable {
    private let task: Task<WhisperKit, Error>
    private let waiter: PreparationWaiter

    init(task: Task<WhisperKit, Error>, waiter: PreparationWaiter) {
        self.task = task
        self.waiter = waiter
    }

    func start() {
        Task { @Sendable [task, waiter] in
            do {
                waiter.complete(.success(try await task.value))
            } catch {
                waiter.complete(.failure(error))
            }
        }
    }
}

private final class LiveCompletionWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var didFinish = false
    private var didCancel = false

    func install(_ continuation: CheckedContinuation<Void, Never>) {
        let shouldResume: Bool
        lock.lock()
        shouldResume = didCancel || didFinish
        if !shouldResume {
            self.continuation = continuation
        }
        lock.unlock()

        if shouldResume {
            continuation.resume()
        }
    }

    func cancel() {
        let continuation: CheckedContinuation<Void, Never>?
        lock.lock()
        didCancel = true
        continuation = self.continuation
        self.continuation = nil
        didFinish = true
        lock.unlock()
        continuation?.resume()
    }
}

private final class LiveCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false
    private var waiters: [LiveCompletionWaiter] = []

    func wait() async {
        let waiter = LiveCompletionWaiter()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                let completed = didComplete
                if !completed {
                    waiters.append(waiter)
                }
                lock.unlock()
                if completed {
                    waiter.cancel()
                }
                waiter.install(continuation)
            }
        } onCancel: {
            waiter.cancel()
        }
    }

    func complete() {
        let pending: [LiveCompletionWaiter]
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.cancel() }
    }
}

private actor LiveWhisperInferenceQueue {
    private final class Job: @unchecked Sendable {
        let id: UUID
        let operation: @Sendable () async throws -> [TranscriptionResult]
        let waiter: InferenceWaiter

        init(
            id: UUID,
            operation: @escaping @Sendable () async throws -> [TranscriptionResult],
            waiter: InferenceWaiter
        ) {
            self.id = id
            self.operation = operation
            self.waiter = waiter
        }
    }

    private var pending: [Job] = []
    private var runningJobID: UUID?

    func run(
        _ operation: @escaping @Sendable () async throws -> [TranscriptionResult]
    ) async throws -> [TranscriptionResult] {
        let id = UUID()
        let waiter = InferenceWaiter()
        let job = Job(id: id, operation: operation, waiter: waiter)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.install(continuation)
                self.enqueue(job)
            }
        } onCancel: {
            waiter.cancel()
            Task { await self.cancel(jobID: id) }
        }
    }

    private func enqueue(_ job: Job) {
        guard !job.waiter.isCancelled else { return }
        pending.append(job)
        startNextIfNeeded()
    }

    private func cancel(jobID: UUID) {
        if let index = pending.firstIndex(where: { $0.id == jobID }) {
            let job = pending.remove(at: index)
            job.waiter.cancel()
            startNextIfNeeded()
        } else if runningJobID == jobID {
            // Do not cancel active WhisperKit work. It must finish before queue
            // advances, so one canceled caller cannot break queue progress.
            pending.first(where: { $0.id == jobID })?.waiter.cancel()
        }
    }

    private func startNextIfNeeded() {
        guard runningJobID == nil else { return }
        guard !pending.isEmpty else { return }

        let job = pending.removeFirst()
        guard !job.waiter.isCancelled else {
            startNextIfNeeded()
            return
        }

        runningJobID = job.id
        Task { [weak self] in
            do {
                let results = try await job.operation()
                await self?.finish(jobID: job.id, waiter: job.waiter, result: .success(results))
            } catch {
                await self?.finish(jobID: job.id, waiter: job.waiter, result: .failure(error))
            }
        }
    }

    private func finish(
        jobID: UUID,
        waiter: InferenceWaiter,
        result: Result<[TranscriptionResult], Error>
    ) {
        guard runningJobID == jobID else { return }
        runningJobID = nil
        waiter.complete(result)
        startNextIfNeeded()
    }
}

private final class InferenceWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[TranscriptionResult], Error>?
    private var didFinish = false
    private var didCancel = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didCancel
    }

    func install(_ continuation: CheckedContinuation<[TranscriptionResult], Error>) {
        let shouldCancel: Bool
        lock.lock()
        shouldCancel = didCancel || didFinish
        if !shouldCancel {
            self.continuation = continuation
        }
        lock.unlock()

        if shouldCancel {
            continuation.resume(throwing: CancellationError())
        }
    }

    func cancel() {
        let continuation: CheckedContinuation<[TranscriptionResult], Error>?
        lock.lock()
        didCancel = true
        continuation = self.continuation
        self.continuation = nil
        didFinish = true
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }

    func complete(_ result: Result<[TranscriptionResult], Error>) {
        let continuation: CheckedContinuation<[TranscriptionResult], Error>?
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        switch result {
        case let .success(results):
            continuation?.resume(returning: results)
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
    }
}

private struct DefaultLiveWhisperModelLoader: LiveWhisperModelLoader {
    func loadModel(for request: WhisperEnginePreparation) async throws -> WhisperKit {
        let resolvedModelName = request.resolvedModelName
        let config = WhisperKitConfig(
            model: resolvedModelName,
            voiceActivityDetector: EnergyVAD(),
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: true
        )
        return try await WhisperKit(config)
    }
}

private struct DefaultLiveWhisperInference: LiveWhisperInference {
    func transcribe(
        model: WhisperKit,
        audioPath: String,
        decodeOptions: DecodingOptions
    ) async throws -> [TranscriptionResult] {
        try await model.transcribe(audioPath: audioPath, decodeOptions: decodeOptions)
    }

    func transcribe(
        model: WhisperKit,
        audioSamples: [Float],
        decodeOptions: DecodingOptions
    ) async throws -> [TranscriptionResult] {
        try await model.transcribe(audioArray: audioSamples, decodeOptions: decodeOptions)
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
        let completion = LiveCompletion()
        var transcriber: AppAudioStreamTranscriber?
        var task: Task<Void, Never>?
        var finalDecodeOptions: DecodingOptions?
        var lifecycle = LiveDictationSessionLifecycle()
        var lastSnapshot: StreamSnapshot = .init()
        var didEmitRecording = false
        var lastPartialTranscript = ""
    }

    private enum FinalTailTestError: Error {
        case failed
    }

    private final class PreparationFlight: @unchecked Sendable {
        let request: WhisperEnginePreparation
        let generation: UInt64
        let task: Task<WhisperKit, Error>

        init(
            request: WhisperEnginePreparation,
            generation: UInt64,
            task: Task<WhisperKit, Error>
        ) {
            self.request = request
            self.generation = generation
            self.task = task
        }
    }

    private let logger = Logger(subsystem: "Whisper", category: "V2Engine")
    private let audioLevelHandler: (@Sendable (Float) -> Void)?
    private let modelLoader: any LiveWhisperModelLoader
    private let inference: any LiveWhisperInference

    private var whisperKit: WhisperKit?
    private var preparedRequest: WhisperEnginePreparation?
    private var preparationGeneration: UInt64 = 0
    private var preparationFlight: PreparationFlight?
    private let inferenceQueue = LiveWhisperInferenceQueue()
    private var activeStream: ActiveStreamSession?
    private var stoppingTasks: [UUID: Task<Void, Never>] = [:]
    private let permissionRequester: @Sendable () async -> Bool

    public init(
        audioLevelHandler: (@Sendable (Float) -> Void)? = nil,
        permissionRequester: @escaping @Sendable () async -> Bool = { await AudioProcessor.requestRecordPermission() }
    ) {
        self.init(
            audioLevelHandler: audioLevelHandler,
            permissionRequester: permissionRequester,
            modelLoader: DefaultLiveWhisperModelLoader(),
            inference: DefaultLiveWhisperInference()
        )
    }

    init(
        audioLevelHandler: (@Sendable (Float) -> Void)? = nil,
        permissionRequester: @escaping @Sendable () async -> Bool = { await AudioProcessor.requestRecordPermission() },
        modelLoader: any LiveWhisperModelLoader,
        inference: any LiveWhisperInference
    ) {
        self.audioLevelHandler = audioLevelHandler
        self.permissionRequester = permissionRequester
        self.modelLoader = modelLoader
        self.inference = inference
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

        try Task.checkCancellation()

        let flight: PreparationFlight
        if let currentFlight = preparationFlight, currentFlight.request == request {
            flight = currentFlight
        } else {
            preparationGeneration &+= 1
            let generation = preparationGeneration
            let modelLoader = self.modelLoader
            let task = Task {
                try await modelLoader.loadModel(for: request)
            }
            flight = PreparationFlight(request: request, generation: generation, task: task)
            preparationFlight = flight
        }

        do {
            let model = try await waitForPreparation(flight.task)
            guard flight.generation == preparationGeneration else {
                return
            }
            whisperKit = model
            preparedRequest = request
            if preparationFlight === flight {
                preparationFlight = nil
            }
        } catch {
            // Canceled callers detach from shared work. Leave flight intact so
            // another caller can join it and so stale completion stays harmless.
            if !Task.isCancelled, preparationFlight === flight {
                preparationFlight = nil
            }
            throw error
        }
    }

    private func waitForPreparation(_ task: Task<WhisperKit, Error>) async throws -> WhisperKit {
        let waiter = PreparationWaiter()
        let observation = PreparationObservation(task: task, waiter: waiter)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.install(continuation)
                observation.start()
            }
        } onCancel: {
            waiter.cancel()
        }
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

        var frozenAudioSamples: [Float]?
        if transcriberNeedsCleanup, let transcriber = activeStream.transcriber {
            // Adapter owns capture shutdown. It waits one microphone tap
            // interval, stops hardware, then returns one immutable tail snapshot.
            frozenAudioSamples = await transcriber.stopStreamTranscription()
            didBeginCapture = await transcriber.didBeginCapture()
        } else {
            // Covers startup cancellation and failures before adapter ownership.
            whisperKit?.audioProcessor.stopRecording()
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

        // Streaming cadence can leave a sub-second tail or an unpublished token.
        // Recheck bounded final context with end clipping disabled.
        let tailResult: Result<StreamSnapshot?, Error>
        if didBeginCapture {
            do {
                tailResult = .success(try await flushFinalAudio(
                    using: activeStream.finalDecodeOptions,
                    lastDecodedSamples: activeStream.lastSnapshot.lastBufferSize,
                    audioSamples: frozenAudioSamples
                ))
            } catch {
                tailResult = .failure(error)
            }
        } else {
            logger.info("Final stream flush skipped: capture never began")
            tailResult = .success(nil)
        }

        guard var finalStream = self.activeStream, finalStream.sessionID == sessionID else { return }
        do {
            let resolution = try resolveFinalTail(
                sessionID: sessionID,
                currentSnapshot: finalStream.lastSnapshot,
                tailResult: tailResult
            )
            finalStream.lastSnapshot = resolution.snapshot
            self.activeStream = finalStream
        } catch {
            finishStoppedStreamWithError(sessionID: sessionID, error: error)
            return
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
        finalStream.completion.complete()

        self.activeStream = nil
    }

    private func flushFinalAudio(
        using decodeOptions: DecodingOptions?,
        lastDecodedSamples: Int,
        audioSamples frozenAudioSamples: [Float]? = nil
    ) async throws -> StreamSnapshot? {
        guard let whisperKit else { return nil }
        guard let decodeOptions else { return nil }

        let audioSamples = frozenAudioSamples ?? Array(whisperKit.audioProcessor.audioSamples)
        return try await flushFinalAudio(
            using: decodeOptions,
            lastDecodedSamples: lastDecodedSamples,
            audioSamples: audioSamples
        )
    }

    private func flushFinalAudio(
        using decodeOptions: DecodingOptions,
        lastDecodedSamples: Int,
        audioSamples: [Float]
    ) async throws -> StreamSnapshot? {
        guard let whisperKit else { return nil }

        guard let window = BoundedFinalAudioWindow.make(
            totalSamples: audioSamples.count,
            lastDecodedSamples: lastDecodedSamples,
            sampleRate: WhisperKit.sampleRate
        ) else {
            logger.info("Final stream flush skipped: no captured audio")
            return nil
        }

        let windowSamples = Array(audioSamples[window.range])
        let offsetSeconds = Double(window.range.lowerBound) / Double(WhisperKit.sampleRate)

        logger.info(
            "Final stream flush starting samples=\(windowSamples.count, privacy: .public) offset=\(offsetSeconds, privacy: .public)s"
        )

        let finalOptions: DecodingOptions = {
            var options = decodeOptions
            options.clipTimestamps = []
            options.windowClipTime = 0
            return options
        }()

        let results = try await inferenceQueue.run { [inference, whisperKit] in
            try await inference.transcribe(
                model: whisperKit,
                audioSamples: windowSamples,
                decodeOptions: finalOptions
            )
        }
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

    private func resolveFinalTail(
        sessionID: UUID,
        currentSnapshot: StreamSnapshot,
        tailResult: Result<StreamSnapshot?, Error>
    ) throws -> (snapshot: StreamSnapshot, usedLiveSnapshotFallback: Bool) {
        switch tailResult {
        case let .success(flushedSnapshot):
            guard let flushedSnapshot else {
                return (currentSnapshot, false)
            }

            let merged = FinalTailTranscriptMerger.merge(
                currentText: currentSnapshot.transcript,
                currentWords: currentSnapshot.words,
                tailText: flushedSnapshot.transcript,
                tailWords: flushedSnapshot.words,
                decodedThroughSeconds: Double(currentSnapshot.lastBufferSize) / Double(WhisperKit.sampleRate)
            )
            var resolvedSnapshot = currentSnapshot
            resolvedSnapshot.transcript = merged.text
            resolvedSnapshot.words = merged.words
            resolvedSnapshot.lastBufferSize = max(
                currentSnapshot.lastBufferSize,
                flushedSnapshot.lastBufferSize
            )
            return (resolvedSnapshot, false)

        case let .failure(error):
            guard !currentSnapshot.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw error
            }

            logger.error(
                "Final stream flush failed; keeping last valid transcript session=\(sessionID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return (currentSnapshot, true)
        }
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
        activeStream.completion.complete()
        self.activeStream = nil
    }

    public func transcribeMemo(_ request: MemoTranscriptionRequest) async throws -> MemoTranscriptionResult {
        if let activeStream {
            await activeStream.completion.wait()
        }
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

        let results = try await inferenceQueue.run { [inference, whisperKit] in
            try await inference.transcribe(
                model: whisperKit,
                audioPath: request.audioFileURL.path,
                decodeOptions: decodeOptions
            )
        }
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
        try await prepare(WhisperEnginePreparation(profile: profile))
    }

    /// Test-only characterization hook. It exercises current final-flush
    /// inference behavior without requiring microphone capture or model files.
    internal func _testFlushFinalAudio(
        audioSamples: [Float],
        lastDecodedSamples: Int
    ) async throws -> String? {
        guard whisperKit != nil else {
            throw WhisperEngineRuntimeError.engineUnavailable
        }
        guard let snapshot = try await flushFinalAudio(
            using: DecodingOptions(),
            lastDecodedSamples: lastDecodedSamples,
            audioSamples: audioSamples
        ) else {
            return nil
        }
        return snapshot.transcript
    }

    internal func _testResolveFinalTail(
        liveTranscript: String,
        liveWords: [TranscriptWord] = [],
        tailTranscript: String? = nil,
        tailWords: [TranscriptWord] = [],
        decodedThroughSeconds: Double = 0,
        outcome: FinalTailTestDecodeOutcome
    ) async throws -> FinalTailTestResolution {
        guard whisperKit != nil else {
            throw WhisperEngineRuntimeError.engineUnavailable
        }

        let currentSnapshot = StreamSnapshot(
            transcript: Self.cleanTranscription(liveTranscript),
            words: liveWords,
            lastBufferSize: Int(decodedThroughSeconds * Double(WhisperKit.sampleRate))
        )
        let tailSnapshot = tailTranscript.map {
            StreamSnapshot(
                transcript: Self.cleanTranscription($0),
                words: tailWords,
                lastBufferSize: currentSnapshot.lastBufferSize
            )
        }
        let tailResult: Result<StreamSnapshot?, Error>
        switch outcome {
        case .success:
            tailResult = .success(tailSnapshot)
        case .noResult:
            tailResult = .success(nil)
        case .failure:
            tailResult = .failure(FinalTailTestError.failed)
        case .canceled:
            tailResult = .failure(CancellationError())
        }

        let resolution = try resolveFinalTail(
            sessionID: UUID(),
            currentSnapshot: currentSnapshot,
            tailResult: tailResult
        )
        return FinalTailTestResolution(
            transcript: resolution.snapshot.transcript,
            words: resolution.snapshot.words,
            usedLiveSnapshotFallback: resolution.usedLiveSnapshotFallback
        )
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

        activeStream.completion.complete()
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
                    _ = await transcriber.stopStreamTranscription()
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
