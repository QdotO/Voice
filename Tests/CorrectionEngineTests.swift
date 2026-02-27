import XCTest

@testable import WhisperShared

final class CorrectionEngineTests: XCTestCase {
    private var engine: CorrectionEngine!
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        engine = CorrectionEngine(baseURL: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - learn()

    func testLearnStoresCorrection() {
        engine.learn(original: "wrld", corrected: "world")
        let result = engine.apply(to: "hello wrld")
        XCTAssertEqual(result, "hello world")
    }

    func testLearnEmptyOriginalIsIgnored() {
        engine.learn(original: "", corrected: "world")
        let result = engine.apply(to: "hello world")
        XCTAssertEqual(result, "hello world")
    }

    func testLearnEmptyCorrectedIsIgnored() {
        engine.learn(original: "hello", corrected: "")
        let result = engine.apply(to: "hello world")
        XCTAssertEqual(result, "hello world")
    }

    func testLearnWhitespaceOnlyIsIgnored() {
        engine.learn(original: "   ", corrected: "hello")
        engine.learn(original: "hello", corrected: "   ")
        let result = engine.apply(to: "hello world")
        XCTAssertEqual(result, "hello world")
    }

    func testLearnCaseOnlyCorrectionNowAllowed() {
        engine.learn(original: "hello", corrected: "Hello")
        let result = engine.apply(to: "test hello")
        XCTAssertEqual(result, "test Hello")
    }

    func testLearnDuplicateOverwritesExisting() {
        engine.learn(original: "tst", corrected: "test1")
        engine.learn(original: "tst", corrected: "test2")
        let result = engine.apply(to: "run tst")
        XCTAssertEqual(result, "run test2")
    }

    func testLearnDuplicateSameValueNoOp() {
        engine.learn(original: "tst", corrected: "test")
        engine.learn(original: "tst", corrected: "test")
        // Should not crash or double-add
        let result = engine.apply(to: "run tst")
        XCTAssertEqual(result, "run test")
    }

    func testLearnTrimsWhitespace() {
        engine.learn(original: "  wrld  ", corrected: "  world  ")
        let result = engine.apply(to: "hello wrld")
        XCTAssertEqual(result, "hello world")
    }

    func testLearnExceeding500TrimsToLatest() {
        for i in 0..<550 {
            engine.learn(original: "orig\(i)", corrected: "fixed\(i)")
        }
        // Early corrections (0-49) should be trimmed
        let earlyResult = engine.apply(to: "orig0")
        XCTAssertEqual(earlyResult, "orig0", "Early corrections should be trimmed")

        // Recent corrections should still work
        let lateResult = engine.apply(to: "orig549")
        XCTAssertEqual(lateResult, "fixed549")
    }

    // MARK: - apply()

    func testApplyNoCorrectionReturnsOriginal() {
        let result = engine.apply(to: "hello world")
        XCTAssertEqual(result, "hello world")
    }

    func testApplyCaseInsensitiveMatching() {
        engine.learn(original: "wrld", corrected: "world")
        let result = engine.apply(to: "hello WRLD")
        XCTAssertEqual(result, "hello world")
    }

    func testApplyMultipleReplacements() {
        engine.learn(original: "teh", corrected: "the")
        let result = engine.apply(to: "teh quick teh slow")
        XCTAssertEqual(result, "the quick the slow")
    }

    func testApplyWordBoundaryMatching() {
        engine.learn(original: "wrld", corrected: "world")
        let result = engine.apply(to: "wrld wrlds")
        // \b boundaries prevent matching inside longer words
        XCTAssertEqual(result, "world wrlds")
    }

    func testApplySpecialCharsWithAdaptiveBoundary() {
        engine.learn(original: "(test)", corrected: "[test]")
        let result = engine.apply(to: "run (test) now")
        XCTAssertEqual(result, "run [test] now")
    }

    func testApplySpecialCharsNotMatchedInsideWord() {
        engine.learn(original: "(test)", corrected: "[test]")
        let result = engine.apply(to: "run pre(test)suf now")
        // "(test)" mid-word should NOT match (adaptive boundary requires whitespace/^/$)
        XCTAssertEqual(result, "run pre(test)suf now")
    }

    func testApplyMultipleCorrectionsApplied() {
        engine.learn(original: "wrld", corrected: "world")
        engine.learn(original: "helo", corrected: "hello")
        let result = engine.apply(to: "helo wrld")
        XCTAssertEqual(result, "hello world")
    }

    // MARK: - extractDifferences()

    func testExtractDifferencesFindsChangedWords() {
        let diffs = engine.extractDifferences(
            original: "the wrld is big",
            corrected: "the world is big"
        )
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs.first?.original, "wrld")
        XCTAssertEqual(diffs.first?.corrected, "world")
    }

    func testExtractDifferencesNoChangesReturnsEmpty() {
        let diffs = engine.extractDifferences(
            original: "hello world",
            corrected: "hello world"
        )
        XCTAssertTrue(diffs.isEmpty)
    }

    func testExtractDifferencesMultipleChanges() {
        let diffs = engine.extractDifferences(
            original: "teh quik fox",
            corrected: "the quick fox"
        )
        XCTAssertGreaterThanOrEqual(diffs.count, 1)
    }

    // MARK: - suggestNewTerms()

    func testSuggestNewTermsCamelCaseDetected() {
        let terms = engine.suggestNewTerms(from: "Use camelCase for naming")
        XCTAssertTrue(terms.contains("camelCase"))
    }

    func testSuggestNewTermsAcronymDetected() {
        // "XYZQ" is an all-caps acronym (2+ chars) not already in shared vocabulary
        let terms = engine.suggestNewTerms(from: "Configure the XYZQ endpoint")
        XCTAssertTrue(terms.contains("XYZQ"))
    }

    func testSuggestNewTermsLongWordsDetected() {
        let terms = engine.suggestNewTerms(from: "refactoring the codebase")
        XCTAssertTrue(terms.contains("refactoring"))
    }

    func testSuggestNewTermsCommonWordsFiltered() {
        let terms = engine.suggestNewTerms(from: "the and for but")
        XCTAssertTrue(terms.isEmpty)
    }

    func testSuggestNewTermsHyphenatedTermDetected() {
        let terms = engine.suggestNewTerms(from: "Use server-rendering for speed")
        XCTAssertTrue(terms.contains("server-rendering"))
    }

    func testSuggestNewTermsSlashTermDetected() {
        // Tokenizer now includes / as internal connector so XY/ZQ stays as one token
        // Using a made-up term to avoid collision with Vocabulary.shared presets
        let terms = engine.suggestNewTerms(from: "Set up XY/ZQ pipeline")
        XCTAssertTrue(terms.contains("XY/ZQ"))
    }

    func testSuggestNewTermsShortWordsExcluded() {
        let terms = engine.suggestNewTerms(from: "go to the map")
        // All words <=3 chars or common words, none should be suggested
        XCTAssertTrue(terms.isEmpty)
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() {
        engine.learn(original: "wrld", corrected: "world")

        // Create a new engine pointing to the same directory
        let engine2 = CorrectionEngine(baseURL: tempDir)
        let result = engine2.apply(to: "hello wrld")
        XCTAssertEqual(result, "hello world")
    }

    // MARK: - Edge Cases (capitalization)

    func testLearnExactDuplicateRejected() {
        engine.learn(original: "hello", corrected: "hello")
        // Exact same string — should be rejected, no correction stored
        let result = engine.apply(to: "hello world")
        XCTAssertEqual(result, "hello world")
    }

    func testCapitalizationCorrectionApplied() {
        engine.learn(original: "swift", corrected: "Swift")
        let result = engine.apply(to: "I love swift programming")
        XCTAssertEqual(result, "I love Swift programming")
    }

    func testCapitalizationCorrectionMatchesCaseInsensitive() {
        engine.learn(original: "swift", corrected: "Swift")
        let result = engine.apply(to: "SWIFT is great")
        XCTAssertEqual(result, "Swift is great")
    }

    func testSpecialCharCorrectionAtStartOfString() {
        engine.learn(original: "(todo)", corrected: "[TODO]")
        let result = engine.apply(to: "(todo) fix this")
        XCTAssertEqual(result, "[TODO] fix this")
    }

    func testSpecialCharCorrectionAtEndOfString() {
        engine.learn(original: "(todo)", corrected: "[TODO]")
        let result = engine.apply(to: "fix this (todo)")
        XCTAssertEqual(result, "fix this [TODO]")
    }
}
