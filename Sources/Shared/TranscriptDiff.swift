import Foundation
import NaturalLanguage

public struct TranscriptDiffHunk: Identifiable, Hashable {
    public enum Kind: String, Codable, Hashable {
        case equal
        case modify
        case replace
        case insert
        case delete
    }

    public let id: UUID
    public let kind: Kind
    public let originalSentences: [String]
    public let suggestedSentences: [String]

    public init(
        id: UUID = UUID(),
        kind: Kind,
        originalSentences: [String],
        suggestedSentences: [String]
    ) {
        self.id = id
        self.kind = kind
        self.originalSentences = originalSentences
        self.suggestedSentences = suggestedSentences
    }

    public var isChange: Bool {
        kind != .equal
    }

    public var originalText: String {
        originalSentences.joined(separator: " ")
    }

    public var suggestedText: String {
        suggestedSentences.joined(separator: " ")
    }
}

public enum TranscriptDiff {
    public static func hunks(original: String, suggested: String) -> [TranscriptDiffHunk] {
        let originalSentences = SentenceTokenizer.sentences(in: original)
        let suggestedSentences = SentenceTokenizer.sentences(in: suggested)

        let originalKeys = originalSentences.map { normalizeKey($0) }
        let suggestedKeys = suggestedSentences.map { normalizeKey($0) }

        let matches = lcsMatches(a: originalKeys, b: suggestedKeys)

        var hunks: [TranscriptDiffHunk] = []
        var i = 0
        var j = 0

        for match in matches {
            let mi = match.aIndex
            let mj = match.bIndex

            if i < mi || j < mj {
                let o = Array(originalSentences[i..<mi])
                let s = Array(suggestedSentences[j..<mj])
                hunks.append(spanHunk(original: o, suggested: s))
            }

            let oSentence = originalSentences[mi]
            let sSentence = suggestedSentences[mj]
            if oSentence == sSentence {
                hunks.append(
                    TranscriptDiffHunk(kind: .equal, originalSentences: [oSentence], suggestedSentences: [sSentence])
                )
            } else {
                hunks.append(
                    TranscriptDiffHunk(kind: .modify, originalSentences: [oSentence], suggestedSentences: [sSentence])
                )
            }

            i = mi + 1
            j = mj + 1
        }

        if i < originalSentences.count || j < suggestedSentences.count {
            let o = Array(originalSentences[i..<originalSentences.count])
            let s = Array(suggestedSentences[j..<suggestedSentences.count])
            hunks.append(spanHunk(original: o, suggested: s))
        }

        return hunks
    }

    public static func apply(hunks: [TranscriptDiffHunk], accepted: Set<UUID>) -> String {
        var sentences: [String] = []
        sentences.reserveCapacity(hunks.reduce(0) { $0 + max($1.originalSentences.count, $1.suggestedSentences.count) })

        for hunk in hunks {
            if !hunk.isChange {
                sentences.append(contentsOf: hunk.originalSentences)
                continue
            }

            if accepted.contains(hunk.id) {
                sentences.append(contentsOf: hunk.suggestedSentences)
            } else {
                sentences.append(contentsOf: hunk.originalSentences)
            }
        }

        return sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func spanHunk(original: [String], suggested: [String]) -> TranscriptDiffHunk {
        if original.isEmpty, !suggested.isEmpty {
            return TranscriptDiffHunk(kind: .insert, originalSentences: [], suggestedSentences: suggested)
        }
        if !original.isEmpty, suggested.isEmpty {
            return TranscriptDiffHunk(kind: .delete, originalSentences: original, suggestedSentences: [])
        }
        return TranscriptDiffHunk(kind: .replace, originalSentences: original, suggestedSentences: suggested)
    }

    private struct Match: Hashable {
        let aIndex: Int
        let bIndex: Int
    }

    private static func lcsMatches(a: [String], b: [String]) -> [Match] {
        guard !a.isEmpty, !b.isEmpty else { return [] }

        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0..<a.count {
            for j in 0..<b.count {
                if a[i] == b[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i][j + 1], dp[i + 1][j])
                }
            }
        }

        var matches: [Match] = []
        var i = a.count
        var j = b.count

        while i > 0, j > 0 {
            if a[i - 1] == b[j - 1] {
                matches.append(Match(aIndex: i - 1, bIndex: j - 1))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return matches.reversed()
    }

    private static func normalizeKey(_ sentence: String) -> String {
        sentence
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum SentenceTokenizer {
    static func sentences(in text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var results: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                results.append(sentence)
            }
            return true
        }

        if results.isEmpty {
            return [trimmed]
        }

        return results
    }
}

