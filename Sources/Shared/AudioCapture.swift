import AVFoundation
import Foundation

/// Captures microphone audio and converts to 16kHz mono for Whisper
public final class AudioCapture {
    private let engine = AVAudioEngine()
    private var isCapturing = false
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var smoothedLevel: Float = 0

    // Whisper requires 16kHz mono audio
    private let targetSampleRate: Double = 16000

    public var onError: ((String) -> Void)?
    public var onLevel: ((Float) -> Void)?

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
        guard !isCapturing else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Validate input format
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioError.invalidInputFormat
        }

        print(
            "[AudioCapture] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels"
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
        isCapturing = true
        print("[AudioCapture] Started capturing")
    }

    /// Stop capturing and return all collected audio
    public func stop() -> [Float] {
        guard isCapturing else { return [] }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false

        bufferLock.lock()
        let audio = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        return audio
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
            onError?("Invalid output frame count: \(outputFrameCount)")
            return
        }

        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCount
            )
        else {
            onError?("Failed to create output buffer (frameCount: \(outputFrameCount))")
            return
        }

        // Track if we've consumed the input buffer (critical fix!)
        var inputBufferConsumed = false

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if inputBufferConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBufferConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            onError?("Audio conversion failed: \(error?.localizedDescription ?? "unknown")")
            return
        }

        // Extract samples and append to buffer
        guard let channelData = outputBuffer.floatChannelData?[0] else { return }
        let samples = Array(
            UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))

        let level = normalizedLevel(samples)
        smoothedLevel = (smoothedLevel * 0.8) + (level * 0.2)
        onLevel?(smoothedLevel)

        bufferLock.lock()
        audioBuffer.append(contentsOf: samples)
        bufferLock.unlock()
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
