import Foundation

public protocol TranscriptionPromptProviding: Sendable {
    func makePrompt() async -> String
}

public struct DefaultTranscriptionPromptProvider: TranscriptionPromptProviding {
    public typealias TermsProvider = @Sendable () -> [String]

    private let vocabularyProvider: TermsProvider
    private let correctionProvider: TermsProvider
    private let limit: Int

    public init(
        vocabularyProvider: @escaping TermsProvider,
        correctionProvider: @escaping TermsProvider,
        limit: Int = 50
    ) {
        self.vocabularyProvider = vocabularyProvider
        self.correctionProvider = correctionProvider
        self.limit = limit
    }

    public func makePrompt() async -> String {
        TranscriptionPromptBuilder.build(
            vocabulary: vocabularyProvider(),
            learnedCorrections: correctionProvider(),
            limit: limit
        )
    }
}

public extension DefaultTranscriptionPromptProvider {
    static func live(limit: Int = 50) -> DefaultTranscriptionPromptProvider {
        DefaultTranscriptionPromptProvider(
            vocabularyProvider: { Vocabulary.shared.enabledTerms.map(\.term) },
            correctionProvider: { CorrectionEngine.shared.learnedCorrectionTexts },
            limit: limit
        )
    }
}
