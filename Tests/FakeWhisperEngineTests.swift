import XCTest

@testable import WhisperShared

final class FakeWhisperEngineTests: XCTestCase {
    func testFakeEngineRecordsPreparationAndStreamsScriptedUpdates() async throws {
        let sessionID = UUID()
        let preparation = WhisperEnginePreparation(profile: .balanced)
        let request = DictationSessionRequest(
            sessionID: sessionID,
            profile: .balanced,
            prompt: "Swift, WhisperKit"
        )
        let updates = [
            DictationSessionUpdate(sessionID: sessionID, state: .preparing),
            DictationSessionUpdate(
                sessionID: sessionID,
                state: .partial,
                transcript: "hello world"
            ),
            DictationSessionUpdate(
                sessionID: sessionID,
                state: .completed,
                transcript: "hello world"
            ),
        ]

        let engine = FakeWhisperEngine(dictationRuns: [ScriptedDictationRun(updates: updates)])

        try await engine.prepare(preparation)
        let stream = try await engine.startDictation(request)
        let collected = try await collect(stream)
        let recordedPreparations = await engine.recordedPreparations()
        let recordedRequests = await engine.recordedDictationRequests()

        XCTAssertEqual(recordedPreparations, [preparation])
        XCTAssertEqual(recordedRequests, [request])
        XCTAssertEqual(collected, updates)
    }

    func testFakeEngineSupportsScriptedTerminalFailures() async throws {
        let sessionID = UUID()
        let engine = FakeWhisperEngine(
            dictationRuns: [
                ScriptedDictationRun(
                    updates: [DictationSessionUpdate(sessionID: sessionID, state: .recording)],
                    terminalError: .scripted("stream failure")
                )
            ]
        )

        do {
            _ = try await collect(
                try await engine.startDictation(
                    DictationSessionRequest(sessionID: sessionID, profile: .fast)
                ))
            XCTFail("Expected scripted failure")
        } catch let error as FakeWhisperEngineError {
            XCTAssertEqual(error, .scripted("stream failure"))
        }
    }

    func testFakeEngineReturnsScriptedMemoResultAndRecordsRequest() async throws {
        let memoID = UUID()
        let request = MemoTranscriptionRequest(
            memoID: memoID,
            audioFileURL: URL(fileURLWithPath: "/tmp/example.m4a"),
            profile: .accurate,
            prompt: "Quincy, Whisper"
        )
        let result = MemoTranscriptionResult(
            memoID: memoID,
            payload: TranscriptionPayload(
                text: "memo transcript",
                words: [TranscriptWord(word: "memo", start: 0, end: 0.2)]
            ),
            durationSeconds: 12
        )
        let engine = FakeWhisperEngine(memoResults: [.success(result)])

        let returned = try await engine.transcribeMemo(request)
        let recordedRequests = await engine.recordedMemoRequests()

        XCTAssertEqual(returned, result)
        XCTAssertEqual(recordedRequests, [request])
    }

    private func collect(_ stream: DictationUpdateStream) async throws -> [DictationSessionUpdate] {
        var updates: [DictationSessionUpdate] = []
        for try await update in stream {
            updates.append(update)
        }
        return updates
    }
}
