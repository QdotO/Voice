import Foundation
import WhisperKit

/// Handles speech-to-text transcription using WhisperKit
final class Transcriber {
    private var whisperKit: WhisperKit?
    private var isLoading = false

    /// Currently loaded model name
    private(set) var modelName: String?

    /// Vocabulary prompt for context
    var vocabularyPrompt: String = ""

    var onModelLoaded: ((Bool, String?) -> Void)?
    var onError: ((String) -> Void)?

    init() {}

    /// Load a Whisper model
    func loadModel(_ model: String = "base.en") async {
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
    func transcribe(_ audio: [Float]) async -> TranscriptionPayload? {
        guard let whisperKit = whisperKit else {
            onError?("Model not loaded")
            return nil
        }

        guard !audio.isEmpty else {
            onError?("Audio buffer is empty")
            return nil
        }

        let durationSeconds = Float(audio.count) / 16000.0
        print("[Transcriber] Audio duration: \(durationSeconds)s, samples: \(audio.count)")

        do {
            // Simplified options for reliability - disabled prefill which can cause issues
            let options = DecodingOptions(
                verbose: true,  // Enable for debugging
                task: .transcribe,
                language: "en",
                temperature: 0.0,
                temperatureFallbackCount: 3,
                topK: 5,
                usePrefillPrompt: false,  // Disabled - can cause issues with nil promptTokens
                usePrefillCache: false,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                wordTimestamps: true,
                clipTimestamps: [],
                promptTokens: nil,
                prefixTokens: nil,
                suppressBlank: false,  // Allow blanks for debugging
                supressTokens: nil,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                firstTokenLogProbThreshold: -1.5,
                noSpeechThreshold: 0.3,  // Lowered from 0.6 - more permissive
                concurrentWorkerCount: 4,
                chunkingStrategy: nil
            )

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

            let words = result.allWords
                .map { word in
                    TranscriptWord(
                        word: word.word.trimmingCharacters(in: .whitespacesAndNewlines),
                        start: Double(word.start),
                        end: Double(word.end)
                    )
                }
                .filter { !$0.word.isEmpty }

            return TranscriptionPayload(text: text, words: words)
        } catch {
            onError?("Transcription failed: \(error.localizedDescription)")
            return nil
        }
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

struct TranscriptionPayload {
    let text: String
    let words: [TranscriptWord]
}
