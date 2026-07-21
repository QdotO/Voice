import Foundation

public enum DictationCoordinatorError: LocalizedError, Sendable {
    case dictationAlreadyRunning

    public var errorDescription: String? {
        switch self {
        case .dictationAlreadyRunning:
            return "A dictation session is already running."
        }
    }
}

public actor DefaultDictationCoordinator: DictationCoordinator {
    public typealias PromptProvider = @Sendable () async -> String
    public typealias LocaleProvider = @Sendable () -> String

    private let engine: any WhisperEngine
    private let settingsStore: any SettingsStore
    private let promptProvider: PromptProvider
    private let localeProvider: LocaleProvider

    private enum SessionPhase {
        case starting
        case running
        case stopping
    }

    private struct SessionState {
        let id: UUID
        var phase: SessionPhase
        var stopRequested = false
        var engineStarted = false
        var didForwardStop = false
    }

    // Keep this reservation from before prompt lookup through stream teardown.
    // Actor methods release isolation at every await, so a UUID assigned only
    // after `engine.startDictation` leaves a window for duplicate starts and
    // orphaned recordings after an early stop.
    private var session: SessionState?

    public init(
        engine: any WhisperEngine,
        settingsStore: any SettingsStore,
        promptProvider: @escaping PromptProvider,
        localeProvider: @escaping LocaleProvider = {
            Locale.current.identifier
        }
    ) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.promptProvider = promptProvider
        self.localeProvider = localeProvider
    }

    public func startDictation() async throws -> DictationUpdateStream {
        if session != nil {
            throw DictationCoordinatorError.dictationAlreadyRunning
        }

        let sessionID = UUID()
        session = SessionState(id: sessionID, phase: .starting)

        do {
            let settings = settingsStore.load()
            let prompt = await promptProvider()
            try throwIfStartCancelled(sessionID)

            let preparation = WhisperEnginePreparation(
                profile: settings.selectedProfile,
                rawModelOverride: settings.rawModelOverride
            )
            let request = DictationSessionRequest(
                sessionID: sessionID,
                profile: settings.selectedProfile,
                localeIdentifier: localeProvider(),
                prompt: prompt
            )

            try await engine.prepare(preparation)
            try throwIfStartCancelled(sessionID)

            let engineStream = try await engine.startDictation(request)
            return try await finishStartingSession(
                sessionID: sessionID,
                engineStream: engineStream
            )
        } catch {
            clearSession(sessionID)
            throw error
        }
    }

    public func stopDictation() async {
        guard let session else { return }
        await stopSession(session.id)
    }

    private func finishStartingSession(
        sessionID: UUID,
        engineStream: DictationUpdateStream
    ) async throws -> DictationUpdateStream {
        guard var session, session.id == sessionID else {
            await engine.stopDictation(sessionID: sessionID)
            throw CancellationError()
        }

        session.engineStarted = true
        if Task.isCancelled {
            session.stopRequested = true
        }

        if session.stopRequested {
            session.phase = .stopping
            self.session = session
            await stopSession(sessionID)
            throw CancellationError()
        }

        session.phase = .running
        self.session = session
        return makeForwardingStream(sessionID: sessionID, engineStream: engineStream)
    }

    private func makeForwardingStream(
        sessionID: UUID,
        engineStream: DictationUpdateStream
    ) -> DictationUpdateStream {
        AsyncThrowingStream { continuation in
            let forwardingTask = Task { [weak self] in
                do {
                    for try await update in engineStream {
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                // A consumer cancellation and an engine-stream termination can
                // race. Route both through one idempotent stop path so neither
                // leaves capture running.
                await self?.stopSession(sessionID)
            }

            continuation.onTermination = { _ in
                forwardingTask.cancel()
                Task { [weak self] in
                    await self?.stopSession(sessionID)
                }
            }
        }
    }

    private func throwIfStartCancelled(_ sessionID: UUID) throws {
        guard var session, session.id == sessionID else {
            throw CancellationError()
        }
        if session.stopRequested || Task.isCancelled {
            session.stopRequested = true
            session.phase = .stopping
            self.session = session
            throw CancellationError()
        }
    }

    private func stopSession(_ sessionID: UUID) async {
        guard var session, session.id == sessionID else { return }

        session.stopRequested = true
        session.phase = .stopping
        if session.didForwardStop {
            self.session = session
            return
        }

        // No engine stream exists until `engine.startDictation` returns. Keep
        // reservation alive so its caller notices stop before it can expose an
        // orphan stream; `finishStartingSession` forwards this pending stop.
        guard session.engineStarted else {
            self.session = session
            return
        }

        session.didForwardStop = true
        self.session = session
        await engine.stopDictation(sessionID: sessionID)
        clearSession(sessionID)
    }

    private func clearSession(_ sessionID: UUID) {
        guard session?.id == sessionID else { return }
        session = nil
    }
}
