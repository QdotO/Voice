import AVFoundation
import Foundation
import XCTest

@testable import WhisperShared

final class AudioFileLoaderTests: XCTestCase {
    func testTinyTailUsesAtLeastOneResampledFramePlusConverterAllowance() throws {
        let backend = FakeAudioFileLoaderBackend(
            sampleRate: 44_100,
            length: 8_193,
            steps: [
                .success(inputFrameCount: 8_192, samples: [0.1]),
                .success(inputFrameCount: 1, samples: [0.2]),
            ]
        )

        let samples = try AudioFileLoader.load(using: backend)

        XCTAssertEqual(samples, [0.1, 0.2])
        XCTAssertEqual(
            backend.requestedOutputCapacities,
            [
                Int(ceil(8_192 * 16_000.0 / 44_100.0)) + AudioFileLoader.converterFrameAllowance,
                1 + AudioFileLoader.converterFrameAllowance,
            ]
        )
    }

    func testOneFrameInputProducesOutputInsteadOfZeroCapacity() throws {
        let backend = FakeAudioFileLoaderBackend(
            sampleRate: 44_100,
            length: 1,
            steps: [.success(inputFrameCount: 1, samples: [0.5])]
        )

        XCTAssertEqual(try AudioFileLoader.load(using: backend), [0.5])
        XCTAssertEqual(backend.requestedOutputCapacities, [1 + AudioFileLoader.converterFrameAllowance])
    }

    func testPublicLoaderConverts44100StereoTo16kMono() throws {
        let url = try makePCM16WAV(sampleRate: 44_100, channels: 2, frameCount: 4_410)
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = try AudioFileLoader.loadPCM16kMono(from: url)

        XCTAssertLessThanOrEqual(abs(samples.count - 1_600), 2)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
    }

    func testPublicLoaderConverts48000StereoTo16kMono() throws {
        let url = try makePCM16WAV(sampleRate: 48_000, channels: 2, frameCount: 4_800)
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = try AudioFileLoader.loadPCM16kMono(from: url)

        XCTAssertLessThanOrEqual(abs(samples.count - 1_600), 2)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
    }

    func testPublicLoaderHandlesOneFrameTail() throws {
        let url = try makePCM16WAV(sampleRate: 44_100, channels: 2, frameCount: 8_193)
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = try AudioFileLoader.loadPCM16kMono(from: url)

        let expectedFrameCount = Double(8_193) * 16_000.0 / 44_100.0
        XCTAssertLessThan(abs(Double(samples.count) - expectedFrameCount), 16)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
    }

    func testInputAllocationFailureIsTypedAndPreservesUnderlyingCapacityContext() {
        let backend = FakeAudioFileLoaderBackend(
            sampleRate: 48_000,
            length: 1,
            steps: [.failure(.inputBufferAllocation(frameCapacity: 1))]
        )

        assertLoaderError(try AudioFileLoader.load(using: backend)) { error in
            guard case let .inputBufferAllocationFailed(frameCapacity) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(frameCapacity, 1)
        }
    }

    func testOutputAllocationFailureIsTypedAndPreservesUnderlyingCapacityContext() {
        let backend = FakeAudioFileLoaderBackend(
            sampleRate: 44_100,
            length: 1,
            steps: [.failure(.outputBufferAllocation(frameCapacity: 2))]
        )

        assertLoaderError(try AudioFileLoader.load(using: backend)) { error in
            guard case let .outputBufferAllocationFailed(frameCapacity) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(frameCapacity, 2)
        }
    }

    func testReadFailureIsTypedAndPreservesUnderlyingError() {
        let underlying = LoaderTestError.read
        let backend = FakeAudioFileLoaderBackend(
            sampleRate: 48_000,
            length: 4,
            steps: [.failure(.read(requestedFrameCount: 4, underlying: underlying))]
        )

        assertLoaderError(try AudioFileLoader.load(using: backend)) { error in
            guard case let .readFailed(requestedFrameCount, cause) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(requestedFrameCount, 4)
            XCTAssertTrue(cause is LoaderTestError)
        }
    }

    func testPartialReadFailsInsteadOfReturningPartialSuccess() {
        let backend = FakeAudioFileLoaderBackend(
            sampleRate: 48_000,
            length: 4,
            steps: [.success(inputFrameCount: 3, samples: [0.1, 0.2, 0.3])]
        )

        assertLoaderError(try AudioFileLoader.load(using: backend)) { error in
            guard case let .partialRead(requestedFrameCount, actualFrameCount) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(requestedFrameCount, 4)
            XCTAssertEqual(actualFrameCount, 3)
        }
    }

    func testConversionFailureIsTypedAndDoesNotReturnEarlierSamples() {
        let underlying = LoaderTestError.conversion
        let backend = FakeAudioFileLoaderBackend(
            sampleRate: 48_000,
            length: 8_193,
            steps: [
                .success(inputFrameCount: 8_192, samples: [0.1]),
                .failure(.conversion(status: "error", underlying: underlying)),
            ]
        )

        assertLoaderError(try AudioFileLoader.load(using: backend)) { error in
            guard case let .conversionFailed(status, cause) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, "error")
            XCTAssertTrue(cause is LoaderTestError)
        }
    }

    private func assertLoaderError(
        _ result: @autoclosure () throws -> [Float],
        inspect: (AudioFileLoaderError) -> Void
    ) {
        do {
            _ = try result()
            XCTFail("Expected AudioFileLoaderError")
        } catch let error as AudioFileLoaderError {
            inspect(error)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makePCM16WAV(sampleRate: Int, channels: Int, frameCount: Int) throws -> URL {
        var data = Data()
        let bytesPerSample = 2
        let blockAlign = channels * bytesPerSample
        let dataSize = frameCount * blockAlign

        data.append(contentsOf: Array("RIFF".utf8))
        appendLittleEndian(UInt32(36 + dataSize), to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(channels), to: &data)
        appendLittleEndian(UInt32(sampleRate), to: &data)
        appendLittleEndian(UInt32(sampleRate * blockAlign), to: &data)
        appendLittleEndian(UInt16(blockAlign), to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        appendLittleEndian(UInt32(dataSize), to: &data)

        for frame in 0..<frameCount {
            for channel in 0..<channels {
                let value = Int16(((frame + channel) % 32) * 256 - 4_000)
                appendLittleEndian(value, to: &data)
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-loader-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

private enum LoaderTestError: Error {
    case read
    case conversion
}

private final class FakeAudioFileLoaderBackend: AudioFileLoaderBackend {
    struct Step {
        let result: Result<AudioFileLoaderChunk, AudioFileLoaderBackendError>

        static func success(inputFrameCount: Int, samples: [Float]) -> Step {
            Step(result: .success(AudioFileLoaderChunk(
                inputFrameCount: inputFrameCount,
                outputSamples: samples
            )))
        }

        static func failure(_ error: AudioFileLoaderBackendError) -> Step {
            Step(result: .failure(error))
        }
    }

    let inputSampleRate: Double
    let inputFrameLength: Int64
    private(set) var inputFramePosition: Int64 = 0
    private(set) var requestedOutputCapacities: [Int] = []
    private var steps: [Step]

    init(sampleRate: Double, length: Int64, steps: [Step]) {
        inputSampleRate = sampleRate
        inputFrameLength = length
        self.steps = steps
    }

    func convertNextChunk(inputFrameCount: Int, outputFrameCapacity: Int) throws -> AudioFileLoaderChunk {
        requestedOutputCapacities.append(outputFrameCapacity)
        let step = steps.removeFirst()
        switch step.result {
        case let .success(chunk):
            inputFramePosition += Int64(chunk.inputFrameCount)
            return chunk
        case let .failure(error):
            throw error
        }
    }
}
