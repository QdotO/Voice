import Foundation

public enum FakeWhisperEngineError: Error, Equatable, Sendable {
    case scripted(String)
}

public struct ScriptedDictationRun: Sendable {
    public let updates: [DictationSessionUpdate]
    public let terminalError: FakeWhisperEngineError?
    public let keepAliveUntilStopped: Bool

    public init(
        updates: [DictationSessionUpdate],
        terminalError: FakeWhisperEngineError? = nil,
        keepAliveUntilStopped: Bool = false
    ) {
        self.updates = updates
        self.terminalError = terminalError
        self.keepAliveUntilStopped = keepAliveUntilStopped
    }
}

public actor FakeWhisperEngine: WhisperEngine {
    private var preparationResults: [Result<Void, FakeWhisperEngineError>]
    private var dictationRuns: [ScriptedDictationRun]
    private var memoResults: [Result<MemoTranscriptionResult, FakeWhisperEngineError>]

    private var preparationHistory: [WhisperEnginePreparation] = []
    private var dictationHistory: [DictationSessionRequest] = []
    private var memoHistory: [MemoTranscriptionRequest] = []
    private var stoppedSessionIDs: [UUID] = []
    private var activeContinuations: [UUID: DictationUpdateStream.Continuation] = [:]

    public init(
        preparationResults: [Result<Void, FakeWhisperEngineError>] = [],
        dictationRuns: [ScriptedDictationRun] = [],
        memoResults: [Result<MemoTranscriptionResult, FakeWhisperEngineError>] = []
    ) {
        self.preparationResults = preparationResults
        self.dictationRuns = dictationRuns
        self.memoResults = memoResults
    }

    public func enqueuePreparationResult(_ result: Result<Void, FakeWhisperEngineError>) {
        preparationResults.append(result)
    }

    public func enqueueDictationRun(_ run: ScriptedDictationRun) {
        dictationRuns.append(run)
    }

    public func enqueueMemoResult(_ result: Result<MemoTranscriptionResult, FakeWhisperEngineError>) {
        memoResults.append(result)
    }

    public func recordedPreparations() -> [WhisperEnginePreparation] {
        preparationHistory
    }

    public func recordedDictationRequests() -> [DictationSessionRequest] {
        dictationHistory
    }

    public func recordedMemoRequests() -> [MemoTranscriptionRequest] {
        memoHistory
    }

    public func recordedStoppedSessions() -> [UUID] {
        stoppedSessionIDs
    }

    public func prepare(_ request: WhisperEnginePreparation) async throws {
        preparationHistory.append(request)
        let result = preparationResults.isEmpty ? .success(()) : preparationResults.removeFirst()
        try result.get()
    }

    public func startDictation(_ request: DictationSessionRequest) async throws -> DictationUpdateStream {
        dictationHistory.append(request)
        let run = dictationRuns.isEmpty
            ? ScriptedDictationRun(updates: [])
            : dictationRuns.removeFirst()

        return AsyncThrowingStream { continuation in
            for update in run.updates {
                continuation.yield(update)
            }
            if run.keepAliveUntilStopped {
                activeContinuations[request.sessionID] = continuation
            } else if let error = run.terminalError {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    public func stopDictation(sessionID: UUID) async {
        stoppedSessionIDs.append(sessionID)
        let continuation = activeContinuations.removeValue(forKey: sessionID)
        continuation?.finish()
    }

    public func transcribeMemo(_ request: MemoTranscriptionRequest) async throws -> MemoTranscriptionResult {
        memoHistory.append(request)
        let result = memoResults.isEmpty
            ? .success(
                MemoTranscriptionResult(
                    memoID: request.memoID,
                    payload: TranscriptionPayload(text: "", words: []),
                    durationSeconds: 0
                ))
            : memoResults.removeFirst()
        return try result.get()
    }
}
