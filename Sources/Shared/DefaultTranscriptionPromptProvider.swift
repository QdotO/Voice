import Foundation

public protocol TranscriptionPromptProviding: Sendable {
    func makePrompt() async -> String
}

public struct DefaultTranscriptionPromptProvider: TranscriptionPromptProviding {
    public typealias TermsProvider = @Sendable () -> [String]
    public typealias AsyncTermsProvider = @Sendable () async -> [String]

    private let vocabularyProvider: AsyncTermsProvider
    private let correctionProvider: AsyncTermsProvider
    private let limit: Int

    public init(
        vocabularyProvider: @escaping TermsProvider,
        correctionProvider: @escaping TermsProvider,
        limit: Int = 50
    ) {
        self.vocabularyProvider = { vocabularyProvider() }
        self.correctionProvider = { correctionProvider() }
        self.limit = limit
    }

    public init(
        asyncVocabularyProvider: @escaping AsyncTermsProvider,
        asyncCorrectionProvider: @escaping AsyncTermsProvider,
        limit: Int = 50
    ) {
        self.vocabularyProvider = asyncVocabularyProvider
        self.correctionProvider = asyncCorrectionProvider
        self.limit = limit
    }

    public func makePrompt() async -> String {
        async let vocabulary = vocabularyProvider()
        async let corrections = correctionProvider()
        return TranscriptionPromptBuilder.build(
            vocabulary: await vocabulary,
            learnedCorrections: await corrections,
            limit: limit
        )
    }
}

public extension DefaultTranscriptionPromptProvider {
    static func live(limit: Int = 50) -> DefaultTranscriptionPromptProvider {
        DefaultTranscriptionPromptProvider(
            asyncVocabularyProvider: { await Vocabulary.shared.enabledTermSnapshot() },
            asyncCorrectionProvider: { await CorrectionEngine.shared.learnedCorrectionSnapshot() },
            limit: limit
        )
    }
}
