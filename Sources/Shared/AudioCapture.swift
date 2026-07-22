// AVFAudio conversion types lack Sendable annotations; converter and buffers stay
// within synchronous conversion calls and do not escape their interop boundary.
@preconcurrency import AVFoundation
import Foundation
import OSLog

internal final class AudioCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var capturing = false
    private var audioBuffer: [Float] = []
    private var smoothedLevel: Float = 0
    private var errorHandler: (@Sendable (String) -> Void)?
    private var levelHandler: (@Sendable (Float) -> Void)?

    func isCapturing() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return capturing
    }

    func setCapturing(_ value: Bool) {
        lock.lock()
        capturing = value
        lock.unlock()
    }

    func drainAudio() -> [Float] {
        lock.lock()
        let audio = audioBuffer
        audioBuffer.removeAll()
        lock.unlock()
        return audio
    }

    func record(samples: [Float], level: Float) -> (Float, (@Sendable (Float) -> Void)?) {
        lock.lock()
        audioBuffer.append(contentsOf: samples)
        smoothedLevel = (smoothedLevel * 0.8) + (level * 0.2)
        let result = (smoothedLevel, levelHandler)
        lock.unlock()
        return result
    }

    func setErrorHandler(_ handler: (@Sendable (String) -> Void)?) {
        lock.lock()
        errorHandler = handler
        lock.unlock()
    }

    func setLevelHandler(_ handler: (@Sendable (Float) -> Void)?) {
        lock.lock()
        levelHandler = handler
        lock.unlock()
    }

    func currentErrorHandler() -> (@Sendable (String) -> Void)? {
        lock.lock()
        let handler = errorHandler
        lock.unlock()
        return handler
    }
}

private final class AudioCaptureConverterInputState: @unchecked Sendable {
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

/// Captures microphone audio and converts to 16kHz mono for Whisper
///
/// AVAudioEngine invokes its tap off the UI actor. Mutable samples, levels, and
/// callbacks live in `AudioCaptureState`; converter state stays call-local.
public final class AudioCapture: @unchecked Sendable {
    private let logger = Logger(subsystem: "Whisper", category: "AudioCapture")
    private let engine = AVAudioEngine()
    private let state = AudioCaptureState()

    // Whisper requires 16kHz mono audio
    private let targetSampleRate: Double = 16000

    public var onError: (@Sendable (String) -> Void)? {
        get { state.currentErrorHandler() }
        set { state.setErrorHandler(newValue) }
    }

    public var onLevel: (@Sendable (Float) -> Void)? {
        get {
            state.currentLevelHandler()
        }
        set { state.setLevelHandler(newValue) }
    }

    public init() {}

    /// Check and request microphone permission
    public func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Start capturing audio
    public func start() throws {
        guard !state.isCapturing() else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Validate input format
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioError.invalidInputFormat
        }

        logger.info(
            "Input format: \(inputFormat.sampleRate, privacy: .public)Hz, \(inputFormat.channelCount, privacy: .public) channels"
        )

        // Create converter to 16kHz mono
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw AudioError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioError.converterCreationFailed
        }

        // Install tap on input
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            self?.processAudio(buffer: buffer, converter: converter, outputFormat: outputFormat)
        }

        engine.prepare()
        try engine.start()
        state.setCapturing(true)
        logger.info("Started capturing audio")
    }

    /// Stop capturing and return all collected audio
    public func stop() -> [Float] {
        guard state.isCapturing() else { return [] }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state.setCapturing(false)
        return state.drainAudio()
    }

    private func processAudio(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        // Calculate output frame count based on sample rate ratio
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard outputFrameCount > 0 else {
            state.currentErrorHandler()?("Invalid output frame count: \(outputFrameCount)")
            return
        }

        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCount
            )
        else {
            state.currentErrorHandler()?("Failed to create output buffer (frameCount: \(outputFrameCount))")
            return
        }

        // AVAudioConverter invokes input provider synchronously for this conversion.
        // Buffer is returned only during this call; it is not stored or used afterward.
        // State object satisfies Sendable checking without letting converter state escape.
        let inputState = AudioCaptureConverterInputState()

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if !inputState.takeInput() {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            state.currentErrorHandler()?(
                "Audio conversion failed: \(error?.localizedDescription ?? "unknown")"
            )
            return
        }

        // Extract samples and append to buffer
        guard let channelData = outputBuffer.floatChannelData?[0] else { return }
        let samples = Array(
            UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))

        let level = normalizedLevel(samples)
        let (smoothedLevel, levelHandler) = state.record(samples: samples, level: level)
        levelHandler?(smoothedLevel)
    }

    private func normalizedLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let mean = sum / Float(samples.count)
        let rms = sqrt(mean)
        if rms <= 0.00001 {
            return 0
        }

        let db = 20 * log10(rms)
        let minDb: Float = -50
        let maxDb: Float = 0
        let clamped = min(max(db, minDb), maxDb)
        return (clamped - minDb) / (maxDb - minDb)
    }
}

private extension AudioCaptureState {
    func currentLevelHandler() -> (@Sendable (Float) -> Void)? {
        lock.lock()
        let handler = levelHandler
        lock.unlock()
        return handler
    }
}

public enum AudioError: Error, LocalizedError {
    case formatCreationFailed
    case converterCreationFailed
    case invalidInputFormat

    public var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .invalidInputFormat:
            return "Invalid input format (no microphone?)"
        }
    }
}
