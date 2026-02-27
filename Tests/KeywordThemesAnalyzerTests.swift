import XCTest

@testable import WhisperShared

final class KeywordThemesAnalyzerTests: XCTestCase {
    private let analyzer = KeywordThemesAnalyzer()

    // MARK: - Frequency Detection

    func testAnalyzeReturnsTopFrequentWords() async throws {
        let result = try await analyzer.analyze(texts: [
            "swift swift swift react react python",
            "swift react python python ruby",
        ])
        XCTAssertTrue(result.bullets.first?.contains("swift") ?? false)
    }

    func testAnalyzeFiltersStopwords() async throws {
        let result = try await analyzer.analyze(texts: [
            "the the the and and and this this this that that that"
        ])
        // All stopwords should be filtered — result should fallback
        let bullet = result.bullets.first ?? ""
        XCTAssertFalse(bullet.contains("the "))
        XCTAssertFalse(bullet.contains("and "))
    }

    func testAnalyzeMinimumLength() async throws {
        let result = try await analyzer.analyze(texts: [
            "go to be of an it"
        ])
        // All words <= 3 chars should be filtered
        let bullet = result.bullets.first ?? ""
        XCTAssertTrue(
            bullet.contains("Not enough") || !bullet.contains(": go"),
            "Short words should be excluded"
        )
    }

    func testAnalyzeTop6Limit() async throws {
        // Provide many unique long words
        let words = (0..<20).map { "keyword\($0)" }
        let text = words.flatMap { Array(repeating: $0, count: 20 - words.firstIndex(of: $0)!) }
            .joined(separator: " ")
        let result = try await analyzer.analyze(texts: [text])

        if let bullet = result.bullets.first, bullet.contains("Frequent topics") {
            let topics = bullet.replacingOccurrences(of: "Frequent topics: ", with: "")
            let count = topics.components(separatedBy: ", ").count
            XCTAssertLessThanOrEqual(count, 6)
        }
    }

    // MARK: - Metadata

    func testAnalyzeConfidenceIs032() async throws {
        let result = try await analyzer.analyze(texts: ["swift programming language"])
        XCTAssertEqual(result.confidence, 0.32)
    }

    func testAnalyzeSourceIsKeywordFallback() async throws {
        let result = try await analyzer.analyze(texts: ["swift programming language"])
        XCTAssertEqual(result.source, "keyword-fallback")
    }

    func testAnalyzeTitleIsLocalThemeScan() async throws {
        let result = try await analyzer.analyze(texts: ["swift programming language"])
        XCTAssertEqual(result.title, "Local theme scan")
    }

    // MARK: - Edge Cases

    func testAnalyzeEmptyInput() async throws {
        let result = try await analyzer.analyze(texts: [])
        XCTAssertFalse(result.bullets.isEmpty)
        XCTAssertTrue(result.bullets.first?.contains("Not enough") ?? false)
    }

    func testAnalyzeAllStopwords() async throws {
        let result = try await analyzer.analyze(texts: [
            "the and that this with from they their"
        ])
        // Should return "Not enough" message since all words are stopped
        XCTAssertTrue(result.bullets.first?.contains("Not enough") ?? false)
    }

    // MARK: - ThemesAnalysis Model

    func testPlaceholder() {
        let placeholder = ThemesAnalysis.placeholder
        XCTAssertEqual(placeholder.confidence, 0)
        XCTAssertEqual(placeholder.source, "placeholder")
        XCTAssertFalse(placeholder.bullets.isEmpty)
    }

    func testThemesAnalysisEquatable() {
        let a = ThemesAnalysis(title: "T", bullets: ["b"], confidence: 0.5, source: "s")
        let b = ThemesAnalysis(title: "T", bullets: ["b"], confidence: 0.5, source: "s")
        XCTAssertEqual(a, b)
    }

    // MARK: - ThemesAnalyzer Facade

    func testThemesAnalyzerEmptyTextsReturnsPlaceholder() async {
        let result = await ThemesAnalyzer.analyze(texts: [], useCopilot: false, copilotEndpoint: "")
        XCTAssertEqual(result, .placeholder)
    }

    func testThemesAnalyzerWhitespaceTextsReturnsPlaceholder() async {
        let result = await ThemesAnalyzer.analyze(
            texts: ["   ", "\n", ""], useCopilot: false, copilotEndpoint: "")
        XCTAssertEqual(result, .placeholder)
    }

    func testThemesAnalyzerNoCopilotUsesKeyword() async {
        let result = await ThemesAnalyzer.analyze(
            texts: ["swift programming language development"],
            useCopilot: false,
            copilotEndpoint: ""
        )
        XCTAssertEqual(result.source, "keyword-fallback")
    }
}
