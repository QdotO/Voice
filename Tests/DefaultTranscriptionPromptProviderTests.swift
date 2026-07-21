import XCTest

@testable import WhisperShared

final class DefaultTranscriptionPromptProviderTests: XCTestCase {
    func testProviderBuildsPromptFromVocabularyAndCorrections() async {
        let provider = DefaultTranscriptionPromptProvider(
            vocabularyProvider: { ["React", "Swift"] },
            correctionProvider: { ["Next.js", "Anthropic"] }
        )

        let prompt = await provider.makePrompt()

        XCTAssertEqual(prompt, "Anthropic, Next.js, React, Swift")
    }

    func testProviderRespectsLimit() async {
        let provider = DefaultTranscriptionPromptProvider(
            vocabularyProvider: { ["Delta", "Echo", "Foxtrot"] },
            correctionProvider: { ["Alpha", "Bravo", "Charlie"] },
            limit: 4
        )

        let prompt = await provider.makePrompt()

        XCTAssertEqual(prompt, "Alpha, Bravo, Charlie, Delta")
    }
}
