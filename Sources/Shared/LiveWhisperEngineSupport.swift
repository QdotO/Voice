import Foundation

/// Session state is deliberately small and synchronous. `LiveWhisperEngine`
/// owns it while async permission and decoder work is in flight.
enum LiveDictationSessionPhase: Sendable, Equatable {
    case starting
    case launching
    case recording
    case stopping
    case finished
}

struct LiveDictationSessionLifecycle: Sendable, Equatable {
    private(set) var phase: LiveDictationSessionPhase = .starting
    private(set) var didStartCapture = false
    private(set) var didInvokeTranscriberStart = false

    mutating func beginLaunch() -> Bool {
        guard phase == .starting else { return false }
        phase = .launching
        return true
    }

    mutating func recordingBegan() -> Bool {
        switch phase {
        case .starting, .launching:
            phase = .recording
            didStartCapture = true
            return false
        case .stopping, .finished:
            didStartCapture = true
            return true
        case .recording:
            return false
        }
    }

    mutating func beginTranscriberStart() -> Bool {
        guard phase == .launching else { return false }
        didInvokeTranscriberStart = true
        return true
    }

    mutating func beginStopping() -> Bool {
        switch phase {
        case .finished, .stopping:
            return false
        case .starting, .launching, .recording:
            phase = .stopping
            return true
        }
    }

    mutating func finish() {
        phase = .finished
    }

    var hasStartedCapture: Bool {
        didStartCapture
    }

    var needsTranscriberCleanup: Bool {
        didStartCapture || didInvokeTranscriberStart
    }

    var isStopping: Bool {
        phase == .stopping
    }
}

struct BoundedFinalAudioWindow: Equatable, Sendable {
    let range: Range<Int>
    let decodedSampleCount: Int

    static let contextSeconds = 2
    static let maximumSeconds = 8

    static func make(
        totalSamples: Int,
        lastDecodedSamples: Int,
        sampleRate: Int
    ) -> BoundedFinalAudioWindow? {
        guard totalSamples > 0, totalSamples > lastDecodedSamples else { return nil }

        let decodedSampleCount = min(max(0, lastDecodedSamples), totalSamples)
        let contextSamples = contextSeconds * sampleRate
        let maximumSamples = maximumSeconds * sampleRate
        let overlapStart = max(0, decodedSampleCount - contextSamples)
        let boundedStart = max(overlapStart, totalSamples - maximumSamples)

        return BoundedFinalAudioWindow(
            range: boundedStart..<totalSamples,
            decodedSampleCount: decodedSampleCount
        )
    }
}

enum FinalTailTranscriptMerger {
    static func merge(
        currentText: String,
        currentWords: [TranscriptWord],
        tailText: String,
        tailWords: [TranscriptWord],
        decodedThroughSeconds: Double
    ) -> (text: String, words: [TranscriptWord]) {
        let current = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = tailText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return (current, currentWords) }
        guard !current.isEmpty else { return (tail, tailWords) }

        let currentTokens = tokens(in: current)
        let tailTokens = tokens(in: tail)
        let overlap = longestSuffixPrefixOverlap(currentTokens, tailTokens)
        let timedTailWords: [TranscriptWord]
        if overlap > 0 {
            timedTailWords = Array(tailWords.dropFirst(min(overlap, tailWords.count)))
        } else {
            timedTailWords = tailWords.filter { $0.end > decodedThroughSeconds + 0.02 }
        }

        let suffix: String
        if overlap > 0 {
            suffix = tailTokens.dropFirst(overlap).joined(separator: " ")
        } else if !timedTailWords.isEmpty {
            suffix = timedTailWords.map(\.word).joined(separator: " ")
        } else {
            // A tail without timing or overlap cannot be safely appended. Keep
            // live text rather than inserting a repeated/divergent phrase.
            suffix = ""
        }

        let mergedText = suffix.isEmpty ? current : "\(current) \(suffix)"
        let mergedWords = currentWords + timedTailWords
        return (mergedText, mergedWords)
    }

    private static func tokens(in text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
    }

    private static func longestSuffixPrefixOverlap(_ current: [String], _ tail: [String]) -> Int {
        let maximum = min(current.count, tail.count)
        guard maximum > 0 else { return 0 }

        for count in stride(from: maximum, through: 1, by: -1) {
            if current.suffix(count).elementsEqual(tail.prefix(count)) {
                return count
            }
        }
        return 0
    }
}

/// Atomic start/stop gate used by app-owned audio stream adapter. Its owner is
/// an actor, so checking permission completion and beginning capture cannot be
/// interleaved by a competing stop call.
struct AppOwnedCaptureGate: Sendable, Equatable {
    private(set) var stopRequested = false
    private(set) var didBeginCapture = false

    mutating func beginCapture() -> Bool {
        guard !stopRequested else { return false }
        didBeginCapture = true
        return true
    }

    mutating func stop() -> Bool {
        guard !stopRequested else { return false }
        stopRequested = true
        return true
    }
}
