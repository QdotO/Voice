import XCTest

@testable import WhisperShared

final class VocabularyTests: XCTestCase {
    private var vocab: Vocabulary!
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        vocab = Vocabulary(baseURL: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Initial State

    func testEmptyVocabHasNoTerms() {
        XCTAssertTrue(vocab.allTerms.isEmpty)
    }

    // MARK: - add

    func testAddStoresNewTerm() {
        vocab.add("Redux", category: "JavaScript/TypeScript")
        XCTAssertEqual(vocab.allTerms.count, 1)
        XCTAssertEqual(vocab.allTerms.first?.term, "Redux")
        XCTAssertEqual(vocab.allTerms.first?.category, "JavaScript/TypeScript")
    }

    func testAddDeduplicatesCaseInsensitive() {
        vocab.add("Redux", category: "JavaScript/TypeScript")
        vocab.add("redux", category: "JavaScript/TypeScript")
        XCTAssertEqual(vocab.allTerms.count, 1)
    }

    func testAddMultipleTerms() {
        vocab.add("Swift", category: "Software Engineering")
        vocab.add("Kotlin", category: "Software Engineering")
        vocab.add("React", category: "Frontend")
        XCTAssertEqual(vocab.allTerms.count, 3)
    }

    func testAddDefaultsToEnabled() {
        vocab.add("Test", category: "Custom")
        XCTAssertTrue(vocab.allTerms.first!.enabled)
    }

    // MARK: - terms(in:)

    func testTermsInCategoryFiltersCorrectly() {
        vocab.add("Swift", category: "Software Engineering")
        vocab.add("React", category: "Frontend")
        vocab.add("Rust", category: "Software Engineering")

        let seTerms = vocab.terms(in: "Software Engineering")
        XCTAssertEqual(seTerms.count, 2)
        XCTAssertTrue(seTerms.allSatisfy { $0.category == "Software Engineering" })
    }

    func testTermsInCategoryEmptyForMissing() {
        vocab.add("Swift", category: "Software Engineering")
        XCTAssertTrue(vocab.terms(in: "NonExistent").isEmpty)
    }

    // MARK: - enabledTerms

    func testEnabledTermsOnlyReturnsEnabled() {
        vocab.add("Swift", category: "Software Engineering")
        vocab.add("Rust", category: "Software Engineering")
        vocab.add("Go", category: "Software Engineering")

        let goTerm = vocab.allTerms.first { $0.term == "Go" }!
        vocab.toggle(goTerm)

        XCTAssertEqual(vocab.enabledTerms.count, 2)
        XCTAssertFalse(vocab.enabledTerms.contains { $0.term == "Go" })
    }

    // MARK: - generatePrompt

    func testGeneratePromptJoinsTerms() {
        vocab.add("Swift", category: "Software Engineering")
        vocab.add("Rust", category: "Software Engineering")
        let prompt = vocab.generatePrompt()
        // Both terms should appear in the prompt
        XCTAssertTrue(prompt.contains("Swift"))
        XCTAssertTrue(prompt.contains("Rust"))
        XCTAssertTrue(prompt.contains(", "))
    }

    func testGeneratePromptEmptyWhenNoEnabled() {
        vocab.add("Swift", category: "Software Engineering")
        let term = vocab.allTerms.first!
        vocab.toggle(term)  // Disable it
        XCTAssertEqual(vocab.generatePrompt(), "")
    }

    func testGeneratePromptLimitsTo50() {
        for i in 0..<100 {
            vocab.add("Term\(i)WithLongSuffix", category: "Custom")
        }
        let prompt = vocab.generatePrompt()
        let termCount = prompt.components(separatedBy: ", ").count
        XCTAssertLessThanOrEqual(termCount, 50)
    }

    // MARK: - remove

    func testRemoveDeletesTerm() {
        vocab.add("Swift", category: "Software Engineering")
        vocab.add("Rust", category: "Software Engineering")
        let swift = vocab.allTerms.first { $0.term == "Swift" }!
        vocab.remove(swift)
        XCTAssertEqual(vocab.allTerms.count, 1)
        XCTAssertFalse(vocab.allTerms.contains { $0.term == "Swift" })
    }

    // MARK: - toggle

    func testToggleFlipsEnabled() {
        vocab.add("Swift", category: "Software Engineering")
        let term = vocab.allTerms.first!
        XCTAssertTrue(term.enabled)

        vocab.toggle(term)
        XCTAssertFalse(vocab.allTerms.first!.enabled)

        vocab.toggle(vocab.allTerms.first!)
        XCTAssertTrue(vocab.allTerms.first!.enabled)
    }

    // MARK: - setCategory

    func testSetCategoryTogglesAllInCategory() {
        vocab.add("Swift", category: "Software Engineering")
        vocab.add("Rust", category: "Software Engineering")
        vocab.add("React", category: "Frontend")

        vocab.setCategory("Software Engineering", enabled: false)
        let seTerms = vocab.terms(in: "Software Engineering")
        XCTAssertTrue(seTerms.allSatisfy { !$0.enabled })

        // Frontend should be unaffected
        let feTerms = vocab.terms(in: "Frontend")
        XCTAssertTrue(feTerms.allSatisfy { $0.enabled })
    }

    func testSetCategoryOnEmptyCategoryNoError() {
        // Should not crash
        vocab.setCategory("NonExistent", enabled: false)
        XCTAssertTrue(vocab.allTerms.isEmpty)
    }

    // MARK: - reset

    func testResetLoadsPresets() {
        let vocab2 = Vocabulary(baseURL: tempDir, loadPresets: true)
        let count = vocab2.allTerms.count
        XCTAssertGreaterThan(count, 50, "Presets should include many terms")
    }

    func testResetClearsCustomTerms() {
        vocab.add("MyCustomTerm", category: "Custom")
        XCTAssertEqual(vocab.allTerms.count, 1)

        vocab.reset()
        // After reset, presets are loaded, custom term is gone
        XCTAssertFalse(vocab.allTerms.contains { $0.term == "MyCustomTerm" })
        XCTAssertGreaterThan(vocab.allTerms.count, 0)  // Presets loaded
    }

    // MARK: - Categories

    func testCategoriesListIsNotEmpty() {
        XCTAssertFalse(Vocabulary.categories.isEmpty)
        XCTAssertTrue(Vocabulary.categories.contains("Software Engineering"))
        XCTAssertTrue(Vocabulary.categories.contains("Custom"))
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() {
        vocab.add("PersistMe", category: "Custom")
        let vocab2 = Vocabulary(baseURL: tempDir)
        XCTAssertEqual(vocab2.allTerms.count, 1)
        XCTAssertEqual(vocab2.allTerms.first?.term, "PersistMe")
    }
}
