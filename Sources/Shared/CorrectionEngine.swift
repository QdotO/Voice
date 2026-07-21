import Foundation
import OSLog

/// Tracks corrections and learns from user edits
public final class CorrectionEngine {
    public static let shared = CorrectionEngine()
    public static let didChangeNotification = Notification.Name("CorrectionEngineDidChange")
    private static let logger = Logger(subsystem: "Whisper", category: "CorrectionEngine")

    private var corrections: [Correction] = []
    private let storage: SQLiteV2Store
    private let maxCorrections = 500

    struct Correction: Codable, Sendable {
        let id: UUID
        let original: String
        let corrected: String
        let timestamp: Date
        let appliedCount: Int

        init(
            id: UUID = UUID(),
            original: String,
            corrected: String,
            timestamp: Date = Date(),
            appliedCount: Int = 0
        ) {
            self.id = id
            self.original = original.lowercased()
            self.corrected = corrected
            self.timestamp = timestamp
            self.appliedCount = appliedCount
        }
    }

    private init() {
        storage = SQLiteV2Store.shared()
        load()
    }

    /// Testable initializer — uses a custom directory for isolation
    init(baseURL: URL) {
        storage = SQLiteV2Store.shared(baseURL: baseURL)
        load()
    }

    // MARK: - Learning

    public var learnedCorrectionTexts: [String] {
        corrections.map(\.corrected)
    }

    public func allCorrections() -> [CorrectionRecord] {
        corrections
            .map {
                CorrectionRecord(
                    id: $0.id,
                    originalText: $0.original,
                    correctedText: $0.corrected,
                    createdAt: $0.timestamp,
                    appliedCount: $0.appliedCount
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func removeCorrection(id: UUID) {
        corrections.removeAll { $0.id == id }
        save()
    }

    public func clearCorrections() {
        corrections.removeAll()
        save()
    }

    /// Learn from a user correction
    public func learn(
        original: String,
        corrected: String,
        suggestVocabulary: Bool = true
    ) {
        let original = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !original.isEmpty, !corrected.isEmpty else { return }
        guard original != corrected else { return }

        // Check if this correction already exists
        if let index = corrections.firstIndex(where: { $0.original == original.lowercased() }) {
            // Update existing correction if different
            if corrections[index].corrected != corrected {
                corrections[index] = Correction(
                    id: corrections[index].id,
                    original: original,
                    corrected: corrected
                )
            }
        } else {
            corrections.append(Correction(original: original, corrected: corrected))
        }

        // Trim old corrections if needed
        if corrections.count > maxCorrections {
            corrections = Array(corrections.suffix(maxCorrections))
        }

        save()

        // If this looks like a vocabulary term, suggest adding it
        if suggestVocabulary, shouldSuggestAsVocab(corrected) {
            let vocab = Vocabulary.shared
            if !vocab.allTerms.contains(where: { $0.term.lowercased() == corrected.lowercased() }) {
                vocab.add(corrected, category: "Custom")
            }
        }
    }

    /// Apply learned corrections to transcribed text
    public func apply(to text: String) -> String {
        var result = text

        for correction in corrections {
            // Build boundary pattern: use \b when edges are word chars,
            // otherwise use lookaround for whitespace/string boundaries
            let escaped = NSRegularExpression.escapedPattern(for: correction.original)
            let startsWithWordChar =
                correction.original.first?.isLetter == true
                || correction.original.first?.isNumber == true
            let endsWithWordChar =
                correction.original.last?.isLetter == true
                || correction.original.last?.isNumber == true
            let leading = startsWithWordChar ? "\\b" : "(?<=\\s|^)"
            let trailing = endsWithWordChar ? "\\b" : "(?=\\s|$)"
            let pattern = "\(leading)\(escaped)\(trailing)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: correction.corrected
                )
            }
        }

        return result
    }

    /// Analyze differences between original and corrected text
    public func extractDifferences(original: String, corrected: String) -> [(
        original: String, corrected: String
    )] {
        let originalWords = tokenize(original)
        let correctedWords = tokenize(corrected)

        var differences: [(original: String, corrected: String)] = []

        // Only infer replacements when token positions align. Insertions and deletions
        // fall back to an exact full-text correction instead of guessing mappings.
        guard originalWords.count == correctedWords.count else { return [] }

        for (originalWord, correctedWord) in zip(originalWords, correctedWords) {
            guard originalWord.lowercased() != correctedWord.lowercased() else { continue }
            guard levenshteinDistance(originalWord, correctedWord) <= 3 else { return [] }
            differences.append((original: originalWord, corrected: correctedWord))
        }

        return differences
    }

    // MARK: - Suggestions

    /// Extract potential vocabulary terms from corrected text
    public func suggestNewTerms(from correctedText: String) -> [String] {
        let words = tokenize(correctedText)
        let vocab = Vocabulary.shared

        return words.filter { word in
            // Filter out common words
            guard word.count >= 3 else { return false }
            guard !isCommonWord(word) else { return false }

            // Not already in vocabulary
            guard !vocab.allTerms.contains(where: { $0.term.lowercased() == word.lowercased() })
            else {
                return false
            }

            return shouldSuggestAsVocab(word)
        }
    }

    // MARK: - Private Helpers

    private func tokenize(_ text: String) -> [String] {
        // Split on whitespace and punctuation, keeping meaningful tokens
        // Includes - ' . / as internal connectors (e.g., CI/CD, Next.js, don't)
        let pattern = "[A-Za-z0-9]+([-'./][A-Za-z0-9]+)*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private func shouldSuggestAsVocab(_ word: String) -> Bool {
        // Suggest if:
        // - Contains mixed case (camelCase, PascalCase)
        // - Contains punctuation (Next.js, CI/CD)
        // - Is an acronym (all caps, 2+ chars)
        // - Longer than 6 chars

        let hasInnerCaps = word.dropFirst().contains(where: { $0.isUppercase })
        let hasPunctuation = word.contains(".") || word.contains("-") || word.contains("/")
        let isAcronym =
            word.count >= 2 && word == word.uppercased() && word.allSatisfy { $0.isLetter }
        let isLong = word.count >= 7

        return hasInnerCaps || hasPunctuation || isAcronym || isLong
    }

    private func isCommonWord(_ word: String) -> Bool {
        let common = Set([
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "must", "can", "need", "dare", "ought",
            "used", "to", "of", "in", "for", "on", "with", "at", "by", "from",
            "as", "into", "through", "during", "before", "after", "above", "below",
            "between", "under", "again", "further", "then", "once", "here", "there",
            "when", "where", "why", "how", "all", "each", "few", "more", "most",
            "other", "some", "such", "no", "nor", "not", "only", "own", "same",
            "so", "than", "too", "very", "just", "and", "but", "if", "or",
            "because", "until", "while", "although", "though", "after",
            "i", "me", "my", "myself", "we", "our", "ours", "ourselves",
            "you", "your", "yours", "yourself", "yourselves", "he", "him",
            "his", "himself", "she", "her", "hers", "herself", "it", "its",
            "itself", "they", "them", "their", "theirs", "themselves",
            "what", "which", "who", "whom", "this", "that", "these", "those",
            "am", "about", "also", "like", "get", "got", "going", "want",
            "know", "think", "say", "said", "see", "make", "go", "come",
        ])
        return common.contains(word.lowercased())
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1.lowercased())
        let s2 = Array(s2.lowercased())
        var dist = [[Int]]()

        for i in 0...s1.count {
            dist.append([Int](repeating: 0, count: s2.count + 1))
            dist[i][0] = i
        }
        for j in 0...s2.count {
            dist[0][j] = j
        }

        for i in 1...s1.count {
            for j in 1...s2.count {
                if s1[i - 1] == s2[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(
                        dist[i - 1][j] + 1,
                        dist[i][j - 1] + 1,
                        dist[i - 1][j - 1] + 1
                    )
                }
            }
        }
        return dist[s1.count][s2.count]
    }

    // MARK: - Persistence

    private func load() {
        do {
            corrections = try storage.fetchCorrections().map {
                Correction(
                    id: $0.id,
                    original: $0.originalText,
                    corrected: $0.correctedText,
                    timestamp: $0.createdAt,
                    appliedCount: $0.appliedCount
                )
            }
        } catch {
            Self.logger.error(
                "Failed to load corrections: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            try storage.replaceCorrections(
                corrections.map {
                    CorrectionRecord(
                        id: $0.id,
                        originalText: $0.original,
                        correctedText: $0.corrected,
                        createdAt: $0.timestamp,
                        appliedCount: $0.appliedCount
                    )
                })
        } catch {
            Self.logger.error(
                "Failed to save corrections: \(error.localizedDescription, privacy: .public)")
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
