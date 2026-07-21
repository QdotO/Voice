import Foundation

public enum WhisperMetric: String, CaseIterable, Sendable {
    case launchToReady
    case hotkeyToRecording
    case speechStartToFirstPartial
    case stopToFinal
    case memoThroughput
}

public enum BenchmarkUnit: String, Sendable {
    case milliseconds
    case realtimeMultiplier
}

public struct BenchmarkMeasurement: Equatable, Sendable {
    public let metric: WhisperMetric
    public let value: Double
    public let unit: BenchmarkUnit
    public let context: [String: String]

    public init(
        metric: WhisperMetric,
        value: Double,
        unit: BenchmarkUnit,
        context: [String: String] = [:]
    ) {
        self.metric = metric
        self.value = value
        self.unit = unit
        self.context = context
    }
}
