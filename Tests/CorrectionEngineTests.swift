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

    func testAllCorrectionsReturnsStoredRecords() {
        engine.learn(original: "wrld", corrected: "world")
        let corrections = engine.allCorrections()

        XCTAssertEqual(corrections.count, 1)
        XCTAssertEqual(corrections.first?.originalText, "wrld")
        XCTAssertEqual(corrections.first?.correctedText, "world")
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
        XCTAssertEqual(diffs.map(\.original), ["teh", "quik"])
        XCTAssertEqual(diffs.map(\.corrected), ["the", "quick"])
    }

    func testExtractDifferencesMapsRepeatedSimilarWordsByPosition() {
        let diffs = engine.extractDifferences(
            original: "wrld wurld",
            corrected: "world words"
        )

        XCTAssertEqual(diffs.map(\.original), ["wrld", "wurld"])
        XCTAssertEqual(diffs.map(\.corrected), ["world", "words"])
    }

    func testExtractDifferencesDoesNotGuessAcrossDeletion() {
        let diffs = engine.extractDifferences(
            original: "hello extra world",
            corrected: "hello world"
        )

        XCTAssertTrue(diffs.isEmpty)
    }

    func testLearnCanSkipVocabularySuggestion() {
        engine.learn(
            original: "hello world",
            corrected: "Hello, world!",
            suggestVocabulary: false
        )

        XCTAssertEqual(engine.apply(to: "hello world"), "Hello, world!")
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

    func testIndependentFacadesRetainInterleavedLearnsAndUpdates() {
        let engine2 = CorrectionEngine(baseURL: tempDir)

        engine.learn(original: "wrld", corrected: "world", suggestVocabulary: false)
        engine2.learn(original: "teh", corrected: "the", suggestVocabulary: false)
        engine.learn(original: "wrld", corrected: "word", suggestVocabulary: false)

        let corrections = engine2.allCorrections()
        XCTAssertEqual(corrections.count, 2)
        XCTAssertEqual(engine.apply(to: "wrld teh"), "word the")
    }

    func testIndependentFacadesConcurrentSameOriginalLearnKeepsOneCorrection() async {
        let engine1 = engine!
        let engine2 = CorrectionEngine(baseURL: tempDir)
        let values = (0..<40).map { "fixed\($0)" }

        await withTaskGroup(of: Void.self) { group in
            for (index, value) in values.enumerated() {
                group.addTask {
                    let target = index.isMultiple(of: 2) ? engine1 : engine2
                    target.learn(
                        original: "same-original",
                        corrected: value,
                        suggestVocabulary: false
                    )
                }
            }
        }

        let corrections = engine.allCorrections()
        XCTAssertEqual(corrections.count, 1)
        XCTAssertTrue(values.contains(corrections[0].correctedText))
    }

    func testIndependentFacadesDeleteAndClearUseDurableCurrentState() {
        let engine2 = CorrectionEngine(baseURL: tempDir)
        engine.learn(original: "wrld", corrected: "world", suggestVocabulary: false)
        engine2.learn(original: "teh", corrected: "the", suggestVocabulary: false)

        let firstID = try! XCTUnwrap(engine.allCorrections().first { $0.originalText == "wrld" }).id
        engine.removeCorrection(id: firstID)

        XCTAssertEqual(engine2.apply(to: "wrld teh"), "wrld the")

        engine2.clearCorrections()
        XCTAssertTrue(engine.allCorrections().isEmpty)
    }

    func testDidChangeNotificationOnlyFiresForEffectiveMutations() throws {
        let notificationCount = LockedSnapshot(0)
        let token = NotificationCenter.default.addObserver(
            forName: CorrectionEngine.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount.withValue { $0 += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        engine.learn(original: "wrld", corrected: "world", suggestVocabulary: false)
        engine.learn(original: "wrld", corrected: "world", suggestVocabulary: false)
        engine.learn(original: "wrld", corrected: "word", suggestVocabulary: false)
        engine.removeCorrection(id: UUID())
        engine.clearCorrections()
        engine.clearCorrections()

        XCTAssertEqual(notificationCount.read(), 3)
    }

    func testRemoveCorrectionDeletesByID() {
        engine.learn(original: "wrld", corrected: "world")
        let correction = try! XCTUnwrap(engine.allCorrections().first)

        engine.removeCorrection(id: correction.id)

        XCTAssertTrue(engine.allCorrections().isEmpty)
        XCTAssertEqual(engine.apply(to: "hello wrld"), "hello wrld")
    }

    func testClearCorrectionsEmptiesEngine() {
        engine.learn(original: "wrld", corrected: "world")
        engine.learn(original: "teh", corrected: "the")

        engine.clearCorrections()

        XCTAssertTrue(engine.allCorrections().isEmpty)
        XCTAssertEqual(engine.apply(to: "wrld teh"), "wrld teh")
    }

    // MARK: - Prompt snapshots

    func testLearnedCorrectionSnapshotIsImmutableAfterMutation() async {
        engine.learn(original: "wrld", corrected: "world", suggestVocabulary: false)

        let snapshot = await engine.learnedCorrectionSnapshot()
        engine.learn(original: "teh", corrected: "the", suggestVocabulary: false)

        XCTAssertEqual(snapshot, ["world"])
        let updatedSnapshot = await engine.learnedCorrectionSnapshot()
        XCTAssertEqual(updatedSnapshot, ["world", "the"])
    }

    func testLearnedCorrectionSnapshotStaysSafeDuringConcurrentMutation() async {
        let expectedCorrections = (0..<80).map { ("orig\($0)", "fixed\($0)") }
        let correctionEngine = engine!

        let snapshots = await withTaskGroup(of: [[String]].self, returning: [[String]].self) {
            group in
            group.addTask {
                for (original, corrected) in expectedCorrections {
                    correctionEngine.learn(
                        original: original,
                        corrected: corrected,
                        suggestVocabulary: false
                    )
                }
                return []
            }
            group.addTask {
                var snapshots = [[String]]()
                for _ in 0..<80 {
                    snapshots.append(await correctionEngine.learnedCorrectionSnapshot())
                }
                return snapshots
            }

            var collected = [[String]]()
            for await childSnapshots in group {
                collected.append(contentsOf: childSnapshots)
            }
            return collected
        }

        let expectedSet = Set(expectedCorrections.map(\.1))
        XCTAssertTrue(snapshots.allSatisfy { $0.allSatisfy { expectedSet.contains($0) } })
        let finalSnapshot = await correctionEngine.learnedCorrectionSnapshot()
        XCTAssertEqual(Set(finalSnapshot), expectedSet)
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
