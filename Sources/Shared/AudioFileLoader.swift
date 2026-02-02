import AVFoundation
import Foundation

public enum AudioFileLoader {
    public static func loadPCM16kMono(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat

        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )
        else {
            throw AudioError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterCreationFailed
        }

        var output: [Float] = []
        let frameCapacity: AVAudioFrameCount = 8192

        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(file.length - file.framePosition)
            let readCount = min(frameCapacity, remaining)

            guard
                let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: inputFormat,
                    frameCapacity: readCount
                )
            else {
                break
            }

            try file.read(into: inputBuffer, frameCount: readCount)

            guard
                let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: AVAudioFrameCount(
                        Double(readCount) * (16000 / inputFormat.sampleRate))
                )
            else {
                break
            }

            var inputConsumed = false
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            guard status != .error, error == nil else {
                throw AudioError.converterCreationFailed
            }

            if let channelData = outputBuffer.floatChannelData?[0] {
                let samples = Array(
                    UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength))
                )
                output.append(contentsOf: samples)
            }
        }

        return output
    }
}
