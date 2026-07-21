import XCTest

@testable import WhisperShared

final class V2PromptBuilderTests: XCTestCase {
    func testBuildPrioritizesCorrectionsAndDeduplicatesCaseInsensitively() {
        let prompt = TranscriptionPromptBuilder.build(
            vocabulary: ["React", "Swift", "react", "CI/CD"],
            learnedCorrections: ["Next.js", "anthropic", "Anthropic"]
        )

        XCTAssertEqual(prompt, "Anthropic, Next.js, CI/CD, React, Swift")
    }

    func testBuildReturnsEmptyStringWhenNoTermsExist() {
        XCTAssertEqual(
            TranscriptionPromptBuilder.build(vocabulary: [], learnedCorrections: []),
            ""
        )
    }

    func testBuildAppliesStableLimitAfterOrdering() {
        let prompt = TranscriptionPromptBuilder.build(
            vocabulary: ["Zulu", "Beta", "Alpha"],
            learnedCorrections: ["delta", "Charlie"],
            limit: 3
        )

        XCTAssertEqual(prompt, "Charlie, delta, Alpha")
    }
}
