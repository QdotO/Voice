import Foundation

public enum StreamingTranscriptAccumulator {
    /// Resolves whole-transcript snapshots emitted by a streaming decoder.
    ///
    /// Invariants:
    /// - Empty, equivalent, or stale snapshots never replace observed text.
    /// - A revision must retain opening context, retain meaningful token
    ///   overlap, and add a novel trailing phrase before it can replace text.
    /// - Repeated multi-word trailing phrases are treated as decoder
    ///   duplication, not forward progress.
    ///
    /// This type intentionally works from text alone. Callers without word
    /// timings cannot safely accept a rewrite that has no new trailing signal.
    public static func moreComplete(_ current: String, _ candidate: String) -> String {
        let current = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.isEmpty else { return current }
        guard !current.isEmpty else { return candidate }

        let currentTokens = tokens(in: current)
        let candidateTokens = tokens(in: candidate)

        guard !candidateTokens.isEmpty else { return current }
        guard !currentTokens.isEmpty else { return candidate }
        guard currentTokens != candidateTokens else { return current }
        guard !containsRepeatedTrailingPhrase(candidateTokens) else { return current }

        let sharedPrefix = sharedPrefixLength(currentTokens, candidateTokens)
        let requiredPrefix = currentTokens.count <= 2 ? 1 : 2
        guard sharedPrefix >= requiredPrefix else { return current }

        let sharedTokens = sharedTokenCount(currentTokens, candidateTokens)
        let shorterSnapshotLength = min(currentTokens.count, candidateTokens.count)
        // A one-word partial has only one safe anchor: literal first-token
        // equality, already enforced by requiredPrefix above. Requiring two
        // shared tokens would freeze normal "Hello" -> "Hello world" growth.
        let requiredSharedTokens: Int
        switch shorterSnapshotLength {
        case 1:
            requiredSharedTokens = 1
        case 2...4:
            requiredSharedTokens = 2
        default:
            requiredSharedTokens = 3
        }
        guard sharedTokens >= requiredSharedTokens else { return current }

        // A shorter corrected final may be authoritative when it corrects an
        // earlier word but carries a new final phrase. A plain shorter prefix
        // has no such evidence and remains a stale snapshot.
        guard hasNovelTrailingPhrase(candidateTokens, comparedTo: currentTokens) else {
            return current
        }

        return candidate
    }

    private static func tokens(in text: String) -> [String] {
        text
            .lowercased()
            .split { character in
                !character.isLetter && !character.isNumber && character != "'"
            }
            .map(String.init)
    }

    private static func sharedPrefixLength(_ lhs: [String], _ rhs: [String]) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }

    private static func sharedTokenCount(_ lhs: [String], _ rhs: [String]) -> Int {
        var remainingCounts = lhs.reduce(into: [:]) { counts, token in
            counts[token, default: 0] += 1
        }

        return rhs.reduce(into: 0) { shared, token in
            guard let remaining = remainingCounts[token], remaining > 0 else { return }
            shared += 1
            remainingCounts[token] = remaining - 1
        }
    }

    private static func hasNovelTrailingPhrase(_ candidate: [String], comparedTo current: [String]) -> Bool {
        let maximumPhraseLength = min(3, candidate.count)
        for phraseLength in stride(from: maximumPhraseLength, through: 1, by: -1) {
            let phrase = Array(candidate.suffix(phraseLength))
            if !contains(phrase, in: current) {
                return true
            }
        }
        return false
    }

    private static func containsRepeatedTrailingPhrase(_ tokens: [String]) -> Bool {
        guard tokens.count >= 4 else { return false }

        // Full-snapshot duplication can be arbitrarily long. This comparison
        // stays linear and catches "whole phrase whole phrase" output.
        if tokens.count.isMultiple(of: 2) {
            let half = tokens.count / 2
            if tokens[..<half].elementsEqual(tokens[half...]) {
                return true
            }
        }

        // Streaming duplication nearly always repeats at candidate tail. Bound
        // this scan so each live partial has fixed duplicate-detection cost.
        let maximumPhraseLength = min(tokens.count / 2, 32)
        guard maximumPhraseLength >= 2 else { return false }

        for phraseLength in 2...maximumPhraseLength {
            let boundary = tokens.count - phraseLength
            let first = tokens[(boundary - phraseLength)..<boundary]
            let second = tokens[boundary...]
            if first.elementsEqual(second) {
                return true
            }
        }

        return false
    }

    private static func contains(_ phrase: [String], in tokens: [String]) -> Bool {
        guard phrase.count <= tokens.count else { return false }

        for start in 0...(tokens.count - phrase.count) {
            if tokens[start..<(start + phrase.count)].elementsEqual(phrase) {
                return true
            }
        }
        return false
    }
}
