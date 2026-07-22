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
        guard totalSamples > 0 else { return nil }

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

enum LiveDecodeSchedulingPolicy {
    static let firstDecodeSeconds: Float = 0.5
    static let subsequentDecodeSeconds: Float = 1.0

    static func shouldSchedule(
        nextBufferSize: Int,
        lastDecodedSamples: Int,
        sampleRate: Int
    ) -> Bool {
        guard nextBufferSize > 0, sampleRate > 0 else { return false }
        let thresholdSeconds = lastDecodedSamples == 0
            ? firstDecodeSeconds
            : subsequentDecodeSeconds
        return Float(nextBufferSize) / Float(sampleRate) >= thresholdSeconds
    }
}

enum LiveCaptureTailPolicy {
    // WhisperKit's microphone tap emits 100 ms buffers. One full tap interval
    // lets audio already in Core Audio reach `audioSamples` before tap removal.
    static let microphoneTapNanoseconds: UInt64 = 100_000_000
    static let settleNanoseconds: UInt64 = 120_000_000
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
        let overlap = longestSuffixPrefixOverlap(
            currentTokens.map(normalizedToken),
            tailTokens.map(normalizedToken)
        )
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
            .map(String.init)
    }

    private static func normalizedToken(_ token: String) -> String {
        token
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
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

enum LiveSnapshotProgress {
    static func shouldReplaceText(
        currentRevision: UInt64,
        candidateRevision: UInt64,
        currentSampleCount: Int,
        candidateSampleCount: Int,
        currentWordEnd: Double,
        candidateWordEnd: Double,
        candidateText: String
    ) -> Bool {
        guard !candidateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard candidateRevision > currentRevision else { return false }

        if candidateSampleCount > currentSampleCount {
            return true
        }
        if candidateWordEnd > 0, candidateWordEnd >= currentWordEnd {
            return true
        }
        if currentWordEnd > 0 {
            return false
        }

        // Progress callbacks and structured segment publication can revise text
        // inside one decoded audio window. Revision order makes that safe even
        // when Whisper changes opening words.
        return candidateSampleCount == currentSampleCount
    }
}
