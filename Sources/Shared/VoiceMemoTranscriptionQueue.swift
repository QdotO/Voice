import Foundation

public enum VoiceMemoTranscriptionQueueError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Memo transcription was cancelled."
        case .failed(let message):
            return message
        }
    }
}

public actor VoiceMemoTranscriptionQueue {
    public struct Job: Sendable {
        public let memoID: UUID
        public let audioFileURL: URL
        public let settings: WhisperSettings
        public let localeIdentifier: String
        public let promptProvider: @Sendable () async -> String

        public init(
            memoID: UUID,
            audioFileURL: URL,
            settings: WhisperSettings,
            localeIdentifier: String,
            promptProvider: @escaping @Sendable () async -> String
        ) {
            self.memoID = memoID
            self.audioFileURL = audioFileURL
            self.settings = settings
            self.localeIdentifier = localeIdentifier
            self.promptProvider = promptProvider
        }
    }

    private let engine: any WhisperEngine
    private var tail: Task<Result<MemoTranscriptionResult, VoiceMemoTranscriptionQueueError>, Never>?

    public init(engine: any WhisperEngine) {
        self.engine = engine
    }

    public func enqueue(
        _ job: Job
    ) async -> Result<MemoTranscriptionResult, VoiceMemoTranscriptionQueueError> {
        let previous = tail
        let engine = self.engine
        let task = Task.detached {
            if let previous {
                _ = await previous.value
            }
            return await Self.run(job: job, engine: engine)
        }
        tail = task
        return await task.value
    }

    private static func run(
        job: Job,
        engine: any WhisperEngine
    ) async -> Result<MemoTranscriptionResult, VoiceMemoTranscriptionQueueError> {
        let startedAt = ContinuousClock().now
        do {
            let preparation = WhisperEnginePreparation(
                profile: job.settings.selectedProfile,
                rawModelOverride: job.settings.rawModelOverride
            )
            try await engine.prepare(preparation)

            let request = MemoTranscriptionRequest(
                memoID: job.memoID,
                audioFileURL: job.audioFileURL,
                profile: job.settings.selectedProfile,
                localeIdentifier: job.localeIdentifier,
                prompt: await job.promptProvider()
            )
            let result = try await engine.transcribeMemo(request)
            let transcript = result.payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let elapsed = max(0.001, seconds(from: startedAt.duration(to: ContinuousClock().now)))
            let throughput = max(0, result.durationSeconds / elapsed)

            await WhisperTelemetry.shared.record(
                BenchmarkMeasurement(
                    metric: .memoThroughput,
                    value: throughput,
                    unit: .realtimeMultiplier,
                    context: [
                        "memo_id": job.memoID.uuidString,
                        "characters": "\(transcript.count)",
                    ]
                )
            )
            return .success(result)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    private static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
