// AVFAudio conversion types lack Sendable annotations; converter and buffers stay
// within synchronous conversion calls and do not escape their interop boundary.
@preconcurrency import AVFoundation
import Foundation

public enum AudioFileLoaderError: Error, LocalizedError {
    case fileOpenFailed(underlying: Error)
    case targetFormatCreationFailed
    case converterCreationFailed(
        inputSampleRate: Double,
        inputChannels: Int,
        outputSampleRate: Double,
        outputChannels: Int
    )
    case inputBufferAllocationFailed(frameCapacity: Int)
    case outputBufferAllocationFailed(frameCapacity: Int)
    case readFailed(requestedFrameCount: Int, underlying: Error)
    case partialRead(requestedFrameCount: Int, actualFrameCount: Int)
    case conversionFailed(status: String, underlying: Error?)

    public var errorDescription: String? {
        switch self {
        case let .fileOpenFailed(underlying):
            return "Audio file could not be opened: \(underlying.localizedDescription)"
        case .targetFormatCreationFailed:
            return "16 kHz mono target format could not be created"
        case let .converterCreationFailed(inputSampleRate, inputChannels, outputSampleRate, outputChannels):
            return "Audio converter could not be created (\(inputSampleRate) Hz/\(inputChannels) ch -> \(outputSampleRate) Hz/\(outputChannels) ch)"
        case let .inputBufferAllocationFailed(frameCapacity):
            return "Input audio buffer allocation failed for \(frameCapacity) frames"
        case let .outputBufferAllocationFailed(frameCapacity):
            return "Output audio buffer allocation failed for \(frameCapacity) frames"
        case let .readFailed(requestedFrameCount, underlying):
            return "Audio read failed for \(requestedFrameCount) frames: \(underlying.localizedDescription)"
        case let .partialRead(requestedFrameCount, actualFrameCount):
            return "Audio read returned \(actualFrameCount) of \(requestedFrameCount) requested frames"
        case let .conversionFailed(status, underlying):
            if let underlying {
                return "Audio conversion failed with status \(status): \(underlying.localizedDescription)"
            }
            return "Audio conversion failed with status \(status)"
        }
    }
}

internal struct AudioFileLoaderChunk {
    let inputFrameCount: Int
    let outputSamples: [Float]
}

internal enum AudioFileLoaderBackendError: Error {
    case inputBufferAllocation(frameCapacity: Int)
    case outputBufferAllocation(frameCapacity: Int)
    case read(requestedFrameCount: Int, underlying: Error)
    case conversion(status: String, underlying: Error?)
}

private final class AudioFileLoaderConverterInputState: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func takeInput() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if consumed {
            return false
        }
        consumed = true
        return true
    }
}

internal protocol AudioFileLoaderBackend: AnyObject {
    var inputSampleRate: Double { get }
    var inputFramePosition: Int64 { get }
    var inputFrameLength: Int64 { get }

    func convertNextChunk(
        inputFrameCount: Int,
        outputFrameCapacity: Int
    ) throws -> AudioFileLoaderChunk
}

public enum AudioFileLoader {
    internal static let outputSampleRate = 16_000.0
    internal static let converterFrameAllowance = 1
    private static let inputFrameCapacity = 8_192

    public static func loadPCM16kMono(from url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioFileLoaderError.fileOpenFailed(underlying: error)
        }

        let inputFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioFileLoaderError.targetFormatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioFileLoaderError.converterCreationFailed(
                inputSampleRate: inputFormat.sampleRate,
                inputChannels: Int(inputFormat.channelCount),
                outputSampleRate: outputSampleRate,
                outputChannels: 1
            )
        }

        let backend = AVAudioFileLoaderBackend(
            file: file,
            inputFormat: inputFormat,
            targetFormat: targetFormat,
            converter: converter
        )
        return try load(using: backend)
    }

    internal static func load(using backend: any AudioFileLoaderBackend) throws -> [Float] {
        guard backend.inputSampleRate.isFinite, backend.inputSampleRate > 0 else {
            throw AudioFileLoaderError.conversionFailed(
                status: "invalid input sample rate",
                underlying: nil
            )
        }

        var output: [Float] = []

        while backend.inputFramePosition < backend.inputFrameLength {
            let remaining = backend.inputFrameLength - backend.inputFramePosition
            let requestedFrameCount = min(Int64(inputFrameCapacity), remaining)
            let requestedFrameCountInt = Int(requestedFrameCount)
            let outputFrameCapacity = try outputFrameCapacity(
                inputFrameCount: requestedFrameCountInt,
                inputSampleRate: backend.inputSampleRate
            )
            let positionBeforeRead = backend.inputFramePosition

            let chunk: AudioFileLoaderChunk
            do {
                chunk = try backend.convertNextChunk(
                    inputFrameCount: requestedFrameCountInt,
                    outputFrameCapacity: outputFrameCapacity
                )
            } catch let error as AudioFileLoaderBackendError {
                throw map(error)
            } catch {
                throw AudioFileLoaderError.conversionFailed(
                    status: "unknown",
                    underlying: error
                )
            }

            guard chunk.inputFrameCount == requestedFrameCountInt else {
                throw AudioFileLoaderError.partialRead(
                    requestedFrameCount: requestedFrameCountInt,
                    actualFrameCount: chunk.inputFrameCount
                )
            }

            guard backend.inputFramePosition > positionBeforeRead else {
                throw AudioFileLoaderError.readFailed(
                    requestedFrameCount: requestedFrameCountInt,
                    underlying: AudioFileLoaderNonProgressingReadError(
                        framePosition: positionBeforeRead
                    )
                )
            }

            output.append(contentsOf: chunk.outputSamples)
        }

        return output
    }

    private static func outputFrameCapacity(
        inputFrameCount: Int,
        inputSampleRate: Double
    ) throws -> Int {
        let resampledFrameCount = Double(inputFrameCount) * outputSampleRate / inputSampleRate
        guard resampledFrameCount.isFinite else {
            throw AudioFileLoaderError.outputBufferAllocationFailed(frameCapacity: 0)
        }

        let maximumFrameCapacity = Int(AVAudioFrameCount.max)
        guard resampledFrameCount <= Double(maximumFrameCapacity - converterFrameAllowance) else {
            throw AudioFileLoaderError.outputBufferAllocationFailed(
                frameCapacity: maximumFrameCapacity
            )
        }

        let roundedFrameCount = max(1, Int(ceil(resampledFrameCount)))
        let (capacity, overflow) = roundedFrameCount.addingReportingOverflow(converterFrameAllowance)
        guard !overflow else {
            throw AudioFileLoaderError.outputBufferAllocationFailed(frameCapacity: Int.max)
        }
        return capacity
    }

    private static func map(_ error: AudioFileLoaderBackendError) -> AudioFileLoaderError {
        switch error {
        case let .inputBufferAllocation(frameCapacity):
            return .inputBufferAllocationFailed(frameCapacity: frameCapacity)
        case let .outputBufferAllocation(frameCapacity):
            return .outputBufferAllocationFailed(frameCapacity: frameCapacity)
        case let .read(requestedFrameCount, underlying):
            return .readFailed(
                requestedFrameCount: requestedFrameCount,
                underlying: underlying
            )
        case let .conversion(status, underlying):
            return .conversionFailed(status: status, underlying: underlying)
        }
    }
}

private final class AVAudioFileLoaderBackend: AudioFileLoaderBackend {
    private let file: AVAudioFile
    private let inputFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter

    var inputSampleRate: Double { inputFormat.sampleRate }
    var inputFramePosition: Int64 { file.framePosition }
    var inputFrameLength: Int64 { file.length }

    init(
        file: AVAudioFile,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat,
        converter: AVAudioConverter
    ) {
        self.file = file
        self.inputFormat = inputFormat
        self.targetFormat = targetFormat
        self.converter = converter
    }

    func convertNextChunk(
        inputFrameCount: Int,
        outputFrameCapacity: Int
    ) throws -> AudioFileLoaderChunk {
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(inputFrameCount)
        ) else {
            throw AudioFileLoaderBackendError.inputBufferAllocation(
                frameCapacity: inputFrameCount
            )
        }

        do {
            try file.read(into: inputBuffer, frameCount: AVAudioFrameCount(inputFrameCount))
        } catch {
            throw AudioFileLoaderBackendError.read(
                requestedFrameCount: inputFrameCount,
                underlying: error
            )
        }

        let actualInputFrameCount = Int(inputBuffer.frameLength)
        guard actualInputFrameCount == inputFrameCount else {
            return AudioFileLoaderChunk(
                inputFrameCount: actualInputFrameCount,
                outputSamples: []
            )
        }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(outputFrameCapacity)
        ) else {
            throw AudioFileLoaderBackendError.outputBufferAllocation(
                frameCapacity: outputFrameCapacity
            )
        }

        // AVAudioConverter invokes input provider synchronously for this conversion.
        // Buffer is returned only during this call; it is not stored or used afterward.
        // State object satisfies Sendable checking without letting converter state escape.
        let inputState = AudioFileLoaderConverterInputState()
        var conversionError: NSError?
        let isEndOfFile = file.framePosition >= file.length
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if !inputState.takeInput() {
                outStatus.pointee = isEndOfFile ? .endOfStream : .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, conversionError == nil else {
            throw AudioFileLoaderBackendError.conversion(
                status: String(describing: status),
                underlying: conversionError
            )
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw AudioFileLoaderBackendError.conversion(
                status: "missing output channel",
                underlying: nil
            )
        }

        return AudioFileLoaderChunk(
            inputFrameCount: actualInputFrameCount,
            outputSamples: Array(
                UnsafeBufferPointer(
                    start: channelData,
                    count: Int(outputBuffer.frameLength)
                )
            )
        )
    }
}

private struct AudioFileLoaderNonProgressingReadError: Error, LocalizedError {
    let framePosition: Int64

    var errorDescription: String? {
        "Audio reader made no progress at frame \(framePosition)"
    }
}
