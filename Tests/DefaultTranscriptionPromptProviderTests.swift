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

    func testProviderAwaitsImmutableAsyncSnapshots() async {
        let source = PromptSnapshotSource(
            vocabulary: ["Swift", "WhisperKit"],
            corrections: ["teh → the"]
        )
        let provider = DefaultTranscriptionPromptProvider(
            asyncVocabularyProvider: { await source.vocabularySnapshot() },
            asyncCorrectionProvider: { await source.correctionSnapshot() }
        )

        let prompt = await provider.makePrompt()

        XCTAssertEqual(prompt, "teh → the, Swift, WhisperKit")

        await source.replace(vocabulary: ["Changed"], corrections: ["Also changed"])
        let changedPrompt = await provider.makePrompt()
        XCTAssertEqual(changedPrompt, "Also changed, Changed")
    }
}

private actor PromptSnapshotSource {
    private var vocabulary: [String]
    private var corrections: [String]

    init(vocabulary: [String], corrections: [String]) {
        self.vocabulary = vocabulary
        self.corrections = corrections
    }

    func vocabularySnapshot() -> [String] { vocabulary }

    func correctionSnapshot() -> [String] { corrections }

    func replace(vocabulary: [String], corrections: [String]) {
        self.vocabulary = vocabulary
        self.corrections = corrections
    }
}
