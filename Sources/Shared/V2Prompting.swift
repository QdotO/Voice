import Foundation

public enum TranscriptionPromptBuilder {
    public static func build(
        vocabulary: [String],
        learnedCorrections: [String],
        limit: Int = 50
    ) -> String {
        guard limit > 0 else { return "" }

        var seen = Set<String>()
        let correctionTerms = uniqueSortedTerms(from: learnedCorrections, seen: &seen)
        let vocabularyTerms = uniqueSortedTerms(from: vocabulary, seen: &seen)
        let ordered = Array((correctionTerms + vocabularyTerms).prefix(limit))

        return ordered.joined(separator: ", ")
    }

    private static func uniqueSortedTerms(from terms: [String], seen: inout Set<String>) -> [String] {
        let cleaned = terms
            .map(normalize)
            .filter { !$0.isEmpty }
            .sorted(by: compareTerms)

        var result: [String] = []
        for term in cleaned {
            let dedupeKey = term.lowercased()
            guard !seen.contains(dedupeKey) else { continue }
            seen.insert(dedupeKey)
            result.append(term)
        }
        return result
    }

    private static func normalize(_ term: String) -> String {
        term
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compareTerms(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.lowercased()
        let right = rhs.lowercased()
        if left == right {
            return lhs < rhs
        }
        return left < right
    }
}
