import Foundation
import WhisperKit

/// Handles speech-to-text transcription using WhisperKit
public final class Transcriber {
    private var whisperKit: WhisperKit?
    private var isLoading = false

    /// Currently loaded model name
    public private(set) var modelName: String?

    /// Vocabulary prompt for context
    public var vocabularyPrompt: String = ""

    public var onModelLoaded: ((Bool, String?) -> Void)?
    public var onError: ((String) -> Void)?

    public init() {}

    /// Load a Whisper model
    public func loadModel(_ model: String = "base.en") async {
        guard !isLoading else { return }
        isLoading = true

        do {
            whisperKit = try await WhisperKit(model: model)
            modelName = model
            isLoading = false
            onModelLoaded?(true, nil)
        } catch {
            isLoading = false
            onModelLoaded?(false, error.localizedDescription)
            onError?("Failed to load model: \(error.localizedDescription)")
        }
    }

    /// Transcribe audio samples
    public func transcribe(_ audio: [Float]) async -> TranscriptionPayload? {
        guard let whisperKit = whisperKit else {
            onError?("Model not loaded")
            return nil
        }

        guard let durationSeconds = validateAndPrepareAudio(audio) else {
            return nil
        }
        print("[Transcriber] Audio duration: \(durationSeconds)s, samples: \(audio.count)")

        do {
            let options = createDecodingOptions()

            let results = try await whisperKit.transcribe(
                audioArray: audio,
                decodeOptions: options
            )

            print("[Transcriber] Results count: \(results.count)")

            guard let result = results.first else {
                print("[Transcriber] No results returned")
                return nil
            }

            print("[Transcriber] Raw text: '\(result.text)'")

            // Clean up the transcription
            let text = cleanTranscription(result.text)
            guard !text.isEmpty else { return nil }

            return makePayload(from: result, cleanedText: text)
        } catch {
            onError?("Transcription failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func validateAndPrepareAudio(_ audio: [Float]) -> Float? {
        guard !audio.isEmpty else {
            onError?("Audio buffer is empty")
            return nil
        }
        return Float(audio.count) / 16000.0
    }

    // Keep decode option defaults in one place to avoid drift across call sites.
    private func createDecodingOptions() -> DecodingOptions {
        DecodingOptions(
            verbose: true,
            task: .transcribe,
            language: "en",
            temperature: 0.0,
            temperatureFallbackCount: 3,
            topK: 5,
            usePrefillPrompt: false,
            usePrefillCache: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            clipTimestamps: [],
            promptTokens: nil,
            prefixTokens: nil,
            suppressBlank: false,
            supressTokens: nil,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.3,
            concurrentWorkerCount: 4,
            chunkingStrategy: nil
        )
    }

    private func makePayload(
        from result: TranscriptionResult,
        cleanedText: String
    ) -> TranscriptionPayload {
        let words = result.allWords
            .map { word in
                TranscriptWord(
                    word: word.word.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: Double(word.start),
                    end: Double(word.end)
                )
            }
            .filter { !$0.word.isEmpty }

        return TranscriptionPayload(text: cleanedText, words: words)
    }

    /// Clean up common Whisper artifacts
    private func cleanTranscription(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only filter these if they are the ENTIRE transcription (hallucinations)
        let fullArtifacts = [
            "[BLANK_AUDIO]",
            "[MUSIC]",
            "[APPLAUSE]",
            "(music)",
            "(applause)",
            "Thank you.",
            "Thanks for watching.",
            "Please subscribe.",
        ]

        // If the entire text is a known hallucination, return empty
        if fullArtifacts.contains(where: { cleaned.lowercased() == $0.lowercased() }) {
            return ""
        }

        // Remove inline artifacts that appear within text
        let inlineArtifacts = ["[BLANK_AUDIO]", "[MUSIC]", "[APPLAUSE]", "..."]
        for artifact in inlineArtifacts {
            cleaned = cleaned.replacingOccurrences(of: artifact, with: "")
        }

        // Remove multiple spaces
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct TranscriptionPayload {
    public let text: String
    public let words: [TranscriptWord]

    public init(text: String, words: [TranscriptWord]) {
        self.text = text
        self.words = words
    }
}
