import XCTest
@testable import WhisperShared

final class WhisperTelemetryTests: XCTestCase {
    override func setUp() async throws {
        await WhisperTelemetry.shared.reset()
    }

    func testMarkAndCompleteRecordsMillisecondsMeasurement() async throws {
        await WhisperTelemetry.shared.mark(.launchToReady, context: ["phase": "launch"])
        try await Task.sleep(nanoseconds: 2_000_000)
        await WhisperTelemetry.shared.complete(.launchToReady, additionalContext: ["state": "ready"])

        let measurements = await WhisperTelemetry.shared.recentMeasurements()
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements[0].metric, .launchToReady)
        XCTAssertEqual(measurements[0].unit, .milliseconds)
        XCTAssertEqual(measurements[0].context["phase"], "launch")
        XCTAssertEqual(measurements[0].context["state"], "ready")
        XCTAssertGreaterThan(measurements[0].value, 0)
    }

    func testRecordStoresRealtimeMeasurement() async {
        await WhisperTelemetry.shared.record(
            BenchmarkMeasurement(
                metric: .memoThroughput,
                value: 1.75,
                unit: .realtimeMultiplier,
                context: ["memo_id": "abc123"]
            )
        )

        let measurements = await WhisperTelemetry.shared.recentMeasurements()
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements[0].metric, .memoThroughput)
        XCTAssertEqual(measurements[0].value, 1.75, accuracy: 0.001)
        XCTAssertEqual(measurements[0].unit, .realtimeMultiplier)
        XCTAssertEqual(measurements[0].context["memo_id"], "abc123")
    }

    func testCancelDropsPendingMetric() async {
        await WhisperTelemetry.shared.mark(.stopToFinal)
        await WhisperTelemetry.shared.cancel(.stopToFinal)
        await WhisperTelemetry.shared.complete(.stopToFinal)

        let measurements = await WhisperTelemetry.shared.recentMeasurements()
        XCTAssertTrue(measurements.isEmpty)
    }
}
