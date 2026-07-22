import Foundation
import WhisperKit
import XCTest

@testable import WhisperShared

final class LiveWhisperEngineLifecycleTests: XCTestCase {
    func testSamePreparationCallsCoalesceIntoOneFlight() async throws {
        let gate = AsyncLatch()
        let model = try await makeModel("same")
        let loader = ControlledModelLoader(models: [model], gates: [gate])
        let engine = makeEngine(loader: loader)
        let request = WhisperEnginePreparation(profile: .balanced, rawModelOverride: "same")

        let firstTask = Task { try await engine.prepare(request) }
        await loader.waitForCallCount(1)
        let secondTask = Task { try await engine.prepare(request) }
        await Task.yield()
        let callCount = await loader.callCount()
        XCTAssertEqual(callCount, 1)

        await gate.release()
        try await firstTask.value
        try await secondTask.value
    }

    func testNewerPreparationPublishesAndStaleCompletionCannotReplaceIt() async throws {
        let olderGate = AsyncLatch()
        let newerGate = AsyncLatch()
        let olderModel = try await makeModel("older")
        let newerModel = try await makeModel("newer")
        let loader = ControlledModelLoader(
            models: [olderModel, newerModel],
            gates: [olderGate, newerGate]
        )
        let inference = ControlledInference(gate: AsyncLatch(released: true))
        let engine = makeEngine(loader: loader, inference: inference)
        let older = WhisperEnginePreparation(profile: .balanced, rawModelOverride: "older")
        let newer = WhisperEnginePreparation(profile: .balanced, rawModelOverride: "newer")

        let olderTask = Task { try await engine.prepare(older) }
        await loader.waitForCallCount(1)
        let newerTask = Task { try await engine.prepare(newer) }
        await loader.waitForCallCount(2)

        await newerGate.release()
        try await newerTask.value
        await olderGate.release()
        try await olderTask.value

        _ = try await engine._testFlushFinalAudio(
            audioSamples: Array(repeating: 0, count: 32_000),
            lastDecodedSamples: 0
        )
        let labels = await inference.modelLabels()
        XCTAssertEqual(labels, ["arc08-newer"])
    }

    func testInferenceNeverOverlaps() async throws {
        let model = try await makeModel("serialized")
        let loader = ControlledModelLoader(
            models: [model],
            gates: [AsyncLatch(released: true)]
        )
        let inferenceGate = AsyncLatch()
        let inference = ControlledInference(gate: inferenceGate)
        let engine = makeEngine(loader: loader, inference: inference)
        try await engine.prepare(WhisperEnginePreparation(profile: .balanced))

        let finalTask = Task {
            try await engine._testFlushFinalAudio(
                audioSamples: Array(repeating: 0, count: 32_000),
                lastDecodedSamples: 0
            )
        }
        await inference.waitForCallCount(1)
        let memoTask = Task {
            try await engine.transcribeMemo(
                MemoTranscriptionRequest(
                    audioFileURL: URL(fileURLWithPath: "/tmp/arc10-memo.wav"),
                    profile: .balanced
                )
            )
        }
        await Task.yield()
        let callCount = await inference.callCount()
        XCTAssertEqual(callCount, 1)

        await inferenceGate.release()
        _ = try await finalTask.value
        await inference.waitForCallCount(2)
        _ = try await memoTask.value
    }

    func testMemoQueuesBehindLiveInferenceAndStartsAfterLiveCompletes() async throws {
        let model = try await makeModel("memo-after-live")
        let loader = ControlledModelLoader(
            models: [model],
            gates: [AsyncLatch(released: true)]
        )
        let inferenceGate = AsyncLatch()
        let inference = ControlledInference(gate: inferenceGate)
        let engine = makeEngine(loader: loader, inference: inference)
        try await engine.prepare(WhisperEnginePreparation(profile: .balanced))

        let liveTask = Task {
            try await engine._testFlushFinalAudio(
                audioSamples: Array(repeating: 0, count: 32_000),
                lastDecodedSamples: 0
            )
        }
        await inference.waitForCallCount(1)
        let memoTask = Task {
            try await engine.transcribeMemo(
                MemoTranscriptionRequest(
                    audioFileURL: URL(fileURLWithPath: "/tmp/arc10-memo-after-live.wav"),
                    profile: .balanced
                )
            )
        }
        await Task.yield()
        let callCount = await inference.callCount()
        XCTAssertEqual(callCount, 1)

        await inferenceGate.release()
        _ = try await liveTask.value
        await inference.waitForCallCount(2)
        _ = try await memoTask.value
        let kinds = await inference.kinds()
        XCTAssertEqual(kinds, [.finalAudio, .memo])
    }

    func testCanceledPreparationWaiterCannotDeadlockSharedFlight() async throws {
        let gate = AsyncLatch()
        let model = try await makeModel("cancellation")
        let loader = ControlledModelLoader(models: [model], gates: [gate])
        let engine = makeEngine(loader: loader)
        let request = WhisperEnginePreparation(profile: .balanced, rawModelOverride: "cancellation")

        let canceledTask = Task { try await engine.prepare(request) }
        await loader.waitForCallCount(1)
        canceledTask.cancel()
        do {
            try await canceledTask.value
            XCTFail("Expected canceled waiter")
        } catch is CancellationError {
            // Expected. Shared load remains usable.
        }

        await gate.release()
        try await engine.prepare(request)
        let callCount = await loader.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testInferenceQueueContinuesAfterThrownOperation() async throws {
        let model = try await makeModel("throwing")
        let loader = ControlledModelLoader(
            models: [model],
            gates: [AsyncLatch(released: true)]
        )
        let inference = ControlledInference(
            gate: AsyncLatch(released: true),
            errors: [.forcedFailure]
        )
        let engine = makeEngine(loader: loader, inference: inference)
        try await engine.prepare(WhisperEnginePreparation(profile: .balanced))

        do {
            _ = try await engine._testFlushFinalAudio(
                audioSamples: Array(repeating: 0, count: 32_000),
                lastDecodedSamples: 0
            )
            XCTFail("Expected forced inference failure")
        } catch is InferenceTestError {
            // Expected.
        }

        _ = try await engine.transcribeMemo(
            MemoTranscriptionRequest(
                audioFileURL: URL(fileURLWithPath: "/tmp/arc10-after-error.wav"),
                profile: .balanced
            )
        )
        let callCount = await inference.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testFinalFlushUsesInjectedInferenceAndKeepsEmptyResultAsNil() async throws {
        let model = try await makeModel("final")
        let loader = ControlledModelLoader(
            models: [model],
            gates: [AsyncLatch(released: true)]
        )
        let inference = ControlledInference(gate: AsyncLatch(released: true))
        let engine = makeEngine(loader: loader, inference: inference)
        try await engine.prepare(WhisperEnginePreparation(profile: .balanced))

        let result = try await engine._testFlushFinalAudio(
            audioSamples: Array(repeating: 0, count: 32_000),
            lastDecodedSamples: 0
        )
        XCTAssertNil(result)
        let callCount = await inference.callCount()
        XCTAssertEqual(callCount, 1)
        let kinds = await inference.kinds()
        XCTAssertEqual(kinds, [.finalAudio])
    }

    func testFinalFlushReturnsInjectedTranscript() async throws {
        let model = try await makeModel("final-transcript")
        let loader = ControlledModelLoader(
            models: [model],
            gates: [AsyncLatch(released: true)]
        )
        let result = TranscriptionResult(
            text: "tail transcript",
            segments: [],
            language: "en",
            timings: TranscriptionTimings()
        )
        let inference = ControlledInference(
            gate: AsyncLatch(released: true),
            finalResults: [result]
        )
        let engine = makeEngine(loader: loader, inference: inference)
        try await engine.prepare(WhisperEnginePreparation(profile: .balanced))

        let transcript = try await engine._testFlushFinalAudio(
            audioSamples: Array(repeating: 0, count: 32_000),
            lastDecodedSamples: 0
        )
        XCTAssertEqual(transcript, "tail transcript")
    }

    func testFinalFlushRechecksTailWhenLiveDecodeReachedCapturedBufferEnd() async throws {
        let model = try await makeModel("final-recheck")
        let loader = ControlledModelLoader(
            models: [model],
            gates: [AsyncLatch(released: true)]
        )
        let result = TranscriptionResult(
            text: "trailing word",
            segments: [],
            language: "en",
            timings: TranscriptionTimings()
        )
        let inference = ControlledInference(
            gate: AsyncLatch(released: true),
            finalResults: [result]
        )
        let engine = makeEngine(loader: loader, inference: inference)
        try await engine.prepare(WhisperEnginePreparation(profile: .balanced))

        let transcript = try await engine._testFlushFinalAudio(
            audioSamples: Array(repeating: 0, count: 48_000),
            lastDecodedSamples: 48_000
        )

        XCTAssertEqual(transcript, "trailing word")
        let callCount = await inference.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testSuccessfulFinalTailMergesWithUsableLiveSnapshot() async throws {
        let engine = try await makePreparedEngine("tail-success")

        let resolution = try await engine._testResolveFinalTail(
            liveTranscript: "live transcript",
            tailTranscript: "tail words",
            tailWords: [
                TranscriptWord(word: "tail", start: 2.0, end: 2.2),
                TranscriptWord(word: "words", start: 2.2, end: 2.5),
            ],
            decodedThroughSeconds: 2.0,
            outcome: .success
        )

        XCTAssertEqual(resolution.transcript, "live transcript tail words")
        XCTAssertFalse(resolution.usedLiveSnapshotFallback)
    }

    func testFailedFinalTailKeepsUsableLiveSnapshotAndRecordsFallback() async throws {
        let engine = try await makePreparedEngine("tail-failure-with-snapshot")

        let resolution = try await engine._testResolveFinalTail(
            liveTranscript: "last valid transcript",
            outcome: .failure
        )

        XCTAssertEqual(resolution.transcript, "last valid transcript")
        XCTAssertTrue(resolution.usedLiveSnapshotFallback)
    }

    func testFailedFinalTailThrowsWithoutUsableLiveSnapshot() async throws {
        let engine = try await makePreparedEngine("tail-failure-without-snapshot")

        do {
            _ = try await engine._testResolveFinalTail(
                liveTranscript: "",
                outcome: .failure
            )
            XCTFail("Expected final-tail failure without usable snapshot")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testCanceledFinalTailKeepsUsableLiveSnapshot() async throws {
        let engine = try await makePreparedEngine("tail-canceled")

        let resolution = try await engine._testResolveFinalTail(
            liveTranscript: "last valid transcript",
            outcome: .canceled
        )

        XCTAssertEqual(resolution.transcript, "last valid transcript")
        XCTAssertTrue(resolution.usedLiveSnapshotFallback)
    }

    func testFinalTailOverlapDoesNotDuplicateSnapshotText() async throws {
        let engine = try await makePreparedEngine("tail-overlap")

        let resolution = try await engine._testResolveFinalTail(
            liveTranscript: "turn left at the next light",
            liveWords: [
                TranscriptWord(word: "turn", start: 0, end: 0.2),
                TranscriptWord(word: "left", start: 0.2, end: 0.4),
                TranscriptWord(word: "at", start: 0.4, end: 0.6),
                TranscriptWord(word: "the", start: 0.6, end: 0.8),
                TranscriptWord(word: "next", start: 0.8, end: 1.0),
                TranscriptWord(word: "light", start: 1.0, end: 1.2),
            ],
            tailTranscript: "the next light and continue",
            tailWords: [
                TranscriptWord(word: "the", start: 1.0, end: 1.2),
                TranscriptWord(word: "next", start: 1.2, end: 1.4),
                TranscriptWord(word: "light", start: 1.4, end: 1.6),
                TranscriptWord(word: "and", start: 1.6, end: 1.8),
                TranscriptWord(word: "continue", start: 1.8, end: 2.0),
            ],
            decodedThroughSeconds: 1.0,
            outcome: .success
        )

        XCTAssertEqual(resolution.transcript, "turn left at the next light and continue")
        XCTAssertEqual(resolution.words.map(\.word), ["turn", "left", "at", "the", "next", "light", "and", "continue"])
    }

    private func makeEngine(
        loader: any LiveWhisperModelLoader,
        inference: (any LiveWhisperInference)? = nil,
        permissionGranted: Bool = true
    ) -> LiveWhisperEngine {
        LiveWhisperEngine(
            permissionRequester: { permissionGranted },
            modelLoader: loader,
            inference: inference ?? ControlledInference(gate: AsyncLatch(released: true))
        )
    }

    private func makePreparedEngine(_ label: String) async throws -> LiveWhisperEngine {
        let model = try await makeModel(label)
        let engine = makeEngine(
            loader: ControlledModelLoader(
                models: [model],
                gates: [AsyncLatch(released: true)]
            )
        )
        try await engine.prepare(WhisperEnginePreparation(profile: .balanced))
        return engine
    }

    private func makeModel(_ label: String) async throws -> WhisperKit {
        let model = try await WhisperKit(
            WhisperKitConfig(
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: false,
                download: false
            )
        )
        model.modelFolder = URL(fileURLWithPath: "/tmp/arc08-\(label)")
        model.tokenizer = TestTokenizer()
        return model
    }
}

private actor AsyncLatch {
    private var released: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(released: Bool = false) {
        self.released = released
    }

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private final class ControlledModelLoader: @unchecked Sendable, LiveWhisperModelLoader {
    private let models: [WhisperKit]
    private let gates: [AsyncLatch]
    private let calls = AsyncCallCounter()

    init(models: [WhisperKit], gates: [AsyncLatch]) {
        self.models = models
        self.gates = gates
    }

    func loadModel(for _: WhisperEnginePreparation) async throws -> WhisperKit {
        let index = await calls.reserve()
        await gates[index].wait()
        return models[index]
    }

    func waitForCallCount(_ expected: Int) async {
        await calls.wait(for: expected)
    }

    func callCount() async -> Int {
        await calls.count
    }
}

private enum InferenceKind: Equatable, Sendable {
    case memo
    case finalAudio
}

private enum InferenceTestError: Error {
    case forcedFailure
}

private final class ControlledInference: @unchecked Sendable, LiveWhisperInference {
    private let gate: AsyncLatch
    private let finalResults: [TranscriptionResult]
    private let errors: [InferenceTestError?]
    private let calls = AsyncCallCounter()
    private let recordedCalls = InferenceCallRecorder()

    init(
        gate: AsyncLatch,
        finalResults: [TranscriptionResult] = [],
        errors: [InferenceTestError?] = []
    ) {
        self.gate = gate
        self.finalResults = finalResults
        self.errors = errors
    }

    func transcribe(
        model: WhisperKit,
        audioPath _: String,
        decodeOptions _: DecodingOptions
    ) async throws -> [TranscriptionResult] {
        let index = await calls.reserve()
        await recordedCalls.record(kind: .memo, modelLabel: model.modelFolder?.lastPathComponent)
        await gate.wait()
        if index < errors.count, let error = errors[index] {
            throw error
        }
        return []
    }

    func transcribe(
        model: WhisperKit,
        audioSamples _: [Float],
        decodeOptions _: DecodingOptions
    ) async throws -> [TranscriptionResult] {
        let index = await calls.reserve()
        await recordedCalls.record(kind: .finalAudio, modelLabel: model.modelFolder?.lastPathComponent)
        await gate.wait()
        if index < errors.count, let error = errors[index] {
            throw error
        }
        return finalResults
    }

    func waitForCallCount(_ expected: Int) async {
        await calls.wait(for: expected)
    }

    func callCount() async -> Int {
        await calls.count
    }

    func kinds() async -> [InferenceKind] {
        await recordedCalls.kinds
    }

    func modelLabels() async -> [String?] {
        await recordedCalls.labels
    }
}

private actor AsyncCallCounter {
    private(set) var count = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func reserve() -> Int {
        let index = count
        record()
        return index
    }

    func record() {
        count += 1
        let ready = waiters.filter { $0.0 <= count }
        waiters.removeAll { $0.0 <= count }
        ready.forEach { $0.1.resume() }
    }

    func wait(for expected: Int) async {
        guard count < expected else { return }
        await withCheckedContinuation { continuation in
            waiters.append((expected, continuation))
        }
    }
}

private actor InferenceCallRecorder {
    private(set) var kinds: [InferenceKind] = []
    private(set) var labels: [String?] = []

    func record(kind: InferenceKind, modelLabel: String?) {
        kinds.append(kind)
        labels.append(modelLabel)
    }
}

private final class TestTokenizer: WhisperTokenizer {
    let specialTokens = SpecialTokens(
        endToken: 1,
        englishToken: 2,
        noSpeechToken: 3,
        noTimestampsToken: 4,
        specialTokenBegin: 5,
        startOfPreviousToken: 6,
        startOfTranscriptToken: 7,
        timeTokenBegin: 8,
        transcribeToken: 9,
        translateToken: 10,
        whitespaceToken: 11
    )
    let allLanguageTokens: Set<Int> = [2]

    func encode(text _: String) -> [Int] { [] }
    func decode(tokens _: [Int]) -> String { "" }
    func convertTokenToId(_: String) -> Int? { nil }
    func convertIdToToken(_: Int) -> String? { nil }
    func splitToWordTokens(tokenIds _: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        ([], [])
    }
}
