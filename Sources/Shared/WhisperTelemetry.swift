import Foundation
import OSLog

public actor WhisperTelemetry {
    private struct PendingMeasurement {
        let startedAt: ContinuousClock.Instant
        let context: [String: String]
    }

    public static let shared = WhisperTelemetry()

    private let clock = ContinuousClock()
    private let logger = Logger(subsystem: "Whisper", category: "Metrics")
    private let signposter = OSSignposter(logger: Logger(subsystem: "Whisper", category: "Signpost"))
    private var pendingMeasurements: [WhisperMetric: PendingMeasurement] = [:]
    private var recentMeasurementsStorage: [BenchmarkMeasurement] = []
    private let measurementLimit = 200

    public init() {}

    public func mark(_ metric: WhisperMetric, context: [String: String] = [:]) {
        pendingMeasurements[metric] = PendingMeasurement(startedAt: clock.now, context: context)
        signposter.emitEvent(Self.signpostName(for: metric))
        logger.debug("Marked metric \(metric.rawValue, privacy: .public)")
    }

    public func complete(_ metric: WhisperMetric, additionalContext: [String: String] = [:]) {
        guard let pendingMeasurement = pendingMeasurements.removeValue(forKey: metric) else { return }

        let elapsed = pendingMeasurement.startedAt.duration(to: clock.now)
        let mergedContext = pendingMeasurement.context.merging(additionalContext) { _, new in new }
        record(
            BenchmarkMeasurement(
                metric: metric,
                value: Self.milliseconds(from: elapsed),
                unit: .milliseconds,
                context: mergedContext
            )
        )
    }

    public func cancel(_ metric: WhisperMetric) {
        pendingMeasurements.removeValue(forKey: metric)
        logger.debug("Cancelled metric \(metric.rawValue, privacy: .public)")
    }

    public func record(_ measurement: BenchmarkMeasurement) {
        recentMeasurementsStorage.append(measurement)
        if recentMeasurementsStorage.count > measurementLimit {
            recentMeasurementsStorage.removeFirst(recentMeasurementsStorage.count - measurementLimit)
        }

        signposter.emitEvent(Self.signpostName(for: measurement.metric))
        logger.notice(
            "Metric \(measurement.metric.rawValue, privacy: .public) = \(measurement.value) \(measurement.unit.rawValue, privacy: .public)"
        )
    }

    public func recentMeasurements() -> [BenchmarkMeasurement] {
        recentMeasurementsStorage
    }

    public func reset() {
        pendingMeasurements.removeAll()
        recentMeasurementsStorage.removeAll()
    }

    private static func signpostName(for metric: WhisperMetric) -> StaticString {
        switch metric {
        case .launchToReady:
            return "launch_to_ready"
        case .hotkeyToRecording:
            return "hotkey_to_recording"
        case .speechStartToFirstPartial:
            return "speech_start_to_first_partial"
        case .stopToFinal:
            return "stop_to_final"
        case .memoThroughput:
            return "memo_throughput"
        }
    }

    private static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        let secondsMs = Double(components.seconds) * 1_000
        let attosecondsMs = Double(components.attoseconds) / 1_000_000_000_000_000
        return max(0, secondsMs + attosecondsMs)
    }
}
