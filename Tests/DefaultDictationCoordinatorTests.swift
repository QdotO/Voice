import XCTest

@testable import WhisperShared

final class DefaultDictationCoordinatorTests: XCTestCase {
    func testStartDictationPreparesEngineAndForwardsPromptAndLocale() async throws {
        let sessionID = UUID()
        let fakeEngine = FakeWhisperEngine(
            dictationRuns: [
                ScriptedDictationRun(
                    updates: [
                        DictationSessionUpdate(sessionID: sessionID, state: .preparing),
                        DictationSessionUpdate(
                            sessionID: sessionID,
                            state: .partial,
                            transcript: "hello"
                        ),
                        DictationSessionUpdate(
                            sessionID: sessionID,
                            state: .completed,
                            transcript: "hello world"
                        ),
                    ]
                )
            ]
        )
        let settings = InMemorySettingsStore(
            settings: WhisperSettings(
                selectedProfile: .accurate,
                rawModelOverride: "small-custom"
            )
        )
        let coordinator = DefaultDictationCoordinator(
            engine: fakeEngine,
            settingsStore: settings,
            promptProvider: { "Swift, WhisperKit" },
            localeProvider: { "en_US" }
        )

        let stream = try await coordinator.startDictation()
        let updates = try await collect(stream)

        let preparations = await fakeEngine.recordedPreparations()
        let requests = await fakeEngine.recordedDictationRequests()

        XCTAssertEqual(
            preparations,
            [WhisperEnginePreparation(profile: .accurate, rawModelOverride: "small-custom")]
        )
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.profile, .accurate)
        XCTAssertEqual(requests.first?.localeIdentifier, "en_US")
        XCTAssertEqual(requests.first?.prompt, "Swift, WhisperKit")
        XCTAssertEqual(updates.map(\.state), [.preparing, .partial, .completed])
    }

    func testStopDictationForwardsSessionIDToEngine() async throws {
        let fakeEngine = FakeWhisperEngine(
            dictationRuns: [
                ScriptedDictationRun(
                    updates: [DictationSessionUpdate(sessionID: UUID(), state: .recording)],
                    keepAliveUntilStopped: true
                )
            ]
        )
        let coordinator = DefaultDictationCoordinator(
            engine: fakeEngine,
            settingsStore: InMemorySettingsStore(),
            promptProvider: { "" },
            localeProvider: { "en_US" }
        )

        _ = try await coordinator.startDictation()
        await Task.yield()
        await Task.yield()
        await coordinator.stopDictation()

        let requests = await fakeEngine.recordedDictationRequests()
        let stoppedSessionIDs = await fakeEngine.recordedStoppedSessions()

        XCTAssertEqual(stoppedSessionIDs, [requests[0].sessionID])
    }

    func testStopDuringPromptCancelsReservedStartBeforePreparation() async {
        let promptBarrier = AsyncBarrier()
        let engine = ControlledWhisperEngine()
        let coordinator = makeCoordinator(engine: engine) {
            await promptBarrier.arriveAndWait()
            return "delayed prompt"
        }

        let startTask = Task {
            do {
                _ = try await coordinator.startDictation()
                return true
            } catch {
                return false
            }
        }

        await promptBarrier.waitUntilReached()
        await coordinator.stopDictation()
        await promptBarrier.release()

        let didStart = await startTask.value
        let preparations = await engine.preparedRequests()
        let starts = await engine.startedRequests()
        let stops = await engine.stoppedSessionIDs()
        XCTAssertFalse(didStart)
        XCTAssertTrue(preparations.isEmpty)
        XCTAssertTrue(starts.isEmpty)
        XCTAssertTrue(stops.isEmpty)
    }

    func testStopDuringPrepareCancelsReservedStartBeforeEngineStart() async {
        let prepareBarrier = AsyncBarrier()
        let engine = ControlledWhisperEngine(prepareBarrier: prepareBarrier)
        let coordinator = makeCoordinator(engine: engine)

        let startTask = Task {
            do {
                _ = try await coordinator.startDictation()
                return true
            } catch {
                return false
            }
        }

        await prepareBarrier.waitUntilReached()
        await coordinator.stopDictation()
        await prepareBarrier.release()

        let didStart = await startTask.value
        let preparations = await engine.preparedRequests()
        let starts = await engine.startedRequests()
        let stops = await engine.stoppedSessionIDs()
        XCTAssertFalse(didStart)
        XCTAssertEqual(preparations.count, 1)
        XCTAssertTrue(starts.isEmpty)
        XCTAssertTrue(stops.isEmpty)
    }

    func testStopDuringEngineStartStopsStartedSessionExactlyOnce() async {
        let startBarrier = AsyncBarrier()
        let engine = ControlledWhisperEngine(startBarrier: startBarrier)
        let coordinator = makeCoordinator(engine: engine)

        let startTask = Task {
            do {
                _ = try await coordinator.startDictation()
                return true
            } catch {
                return false
            }
        }

        await startBarrier.waitUntilReached()
        await coordinator.stopDictation()
        await startBarrier.release()

        let didStart = await startTask.value
        let requests = await engine.startedRequests()
        let stops = await engine.stoppedSessionIDs()
        XCTAssertFalse(didStart)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(stops, [requests[0].sessionID])
    }

    func testConcurrentStartsRejectSecondStartWhileFirstIsPreparing() async throws {
        let prepareBarrier = AsyncBarrier()
        let engine = ControlledWhisperEngine(prepareBarrier: prepareBarrier)
        let coordinator = makeCoordinator(engine: engine)

        let firstStart = Task {
            try await coordinator.startDictation()
        }

        await prepareBarrier.waitUntilReached()
        do {
            _ = try await coordinator.startDictation()
            XCTFail("Second start should fail while first start owns reservation")
        } catch let error as DictationCoordinatorError {
            XCTAssertEqual(error.errorDescription, "A dictation session is already running.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await prepareBarrier.release()
        _ = try await firstStart.value
        await coordinator.stopDictation()

        let preparations = await engine.preparedRequests()
        let starts = await engine.startedRequests()
        XCTAssertEqual(preparations.count, 1)
        XCTAssertEqual(starts.count, 1)
    }

    private func collect(_ stream: DictationUpdateStream) async throws -> [DictationSessionUpdate] {
        var updates: [DictationSessionUpdate] = []
        for try await update in stream {
            updates.append(update)
        }
        return updates
    }

    private func makeCoordinator(
        engine: any WhisperEngine,
        promptProvider: @escaping DefaultDictationCoordinator.PromptProvider = { "" }
    ) -> DefaultDictationCoordinator {
        DefaultDictationCoordinator(
            engine: engine,
            settingsStore: InMemorySettingsStore(),
            promptProvider: promptProvider,
            localeProvider: { "en_US" }
        )
    }
}

private actor AsyncBarrier {
    private var hasArrived = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func arriveAndWait() async {
        hasArrived = true
        let waiters = arrivalWaiters
        arrivalWaiters.removeAll()
        waiters.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilReached() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { continuation in
            arrivalWaiters.append(continuation)
        }
    }

    func release() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor ControlledWhisperEngine: WhisperEngine {
    private let prepareBarrier: AsyncBarrier?
    private let startBarrier: AsyncBarrier?

    private var preparations: [WhisperEnginePreparation] = []
    private var starts: [DictationSessionRequest] = []
    private var stops: [UUID] = []
    private var activeContinuations: [UUID: DictationUpdateStream.Continuation] = [:]

    init(prepareBarrier: AsyncBarrier? = nil, startBarrier: AsyncBarrier? = nil) {
        self.prepareBarrier = prepareBarrier
        self.startBarrier = startBarrier
    }

    func prepare(_ request: WhisperEnginePreparation) async throws {
        preparations.append(request)
        await prepareBarrier?.arriveAndWait()
    }

    func startDictation(_ request: DictationSessionRequest) async throws -> DictationUpdateStream {
        starts.append(request)
        await startBarrier?.arriveAndWait()

        var capturedContinuation: DictationUpdateStream.Continuation?
        let stream = AsyncThrowingStream<DictationSessionUpdate, Error> { continuation in
            capturedContinuation = continuation
        }
        guard let capturedContinuation else {
            fatalError("Stream continuation was not created")
        }
        activeContinuations[request.sessionID] = capturedContinuation
        return stream
    }

    func stopDictation(sessionID: UUID) async {
        stops.append(sessionID)
        activeContinuations.removeValue(forKey: sessionID)?.finish()
    }

    func transcribeMemo(_ request: MemoTranscriptionRequest) async throws -> MemoTranscriptionResult {
        MemoTranscriptionResult(
            memoID: request.memoID,
            payload: TranscriptionPayload(text: "", words: []),
            durationSeconds: 0
        )
    }

    func preparedRequests() -> [WhisperEnginePreparation] { preparations }
    func startedRequests() -> [DictationSessionRequest] { starts }
    func stoppedSessionIDs() -> [UUID] { stops }
}
