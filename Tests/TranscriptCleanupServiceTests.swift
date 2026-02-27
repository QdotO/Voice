import XCTest

@testable import WhisperShared

final class TranscriptCleanupServiceTests: XCTestCase {
    // MARK: - basicCleanup

    func testBasicCleanupCarriageReturns() {
        let result = TranscriptCleanupService.basicCleanup("line1\r\nline2")
        XCTAssertEqual(result, "line1\nline2")
    }

    func testBasicCleanupCarriageReturnOnly() {
        let result = TranscriptCleanupService.basicCleanup("line1\rline2")
        XCTAssertEqual(result, "line1\nline2")
    }

    func testBasicCleanupMultipleNewlines() {
        let result = TranscriptCleanupService.basicCleanup("A\n\n\nB")
        XCTAssertEqual(result, "A\n\nB")
    }

    func testBasicCleanupManyNewlines() {
        let result = TranscriptCleanupService.basicCleanup("A\n\n\n\n\n\nB")
        XCTAssertEqual(result, "A\n\nB")
    }

    func testBasicCleanupTabToSpace() {
        let result = TranscriptCleanupService.basicCleanup("A\tB")
        XCTAssertEqual(result, "A B")
    }

    func testBasicCleanupMultipleSpaces() {
        let result = TranscriptCleanupService.basicCleanup("hello    world")
        XCTAssertEqual(result, "hello world")
    }

    func testBasicCleanupSpaceBeforeComma() {
        let result = TranscriptCleanupService.basicCleanup("hello , world")
        XCTAssertEqual(result, "hello, world")
    }

    func testBasicCleanupSpaceBeforePeriod() {
        let result = TranscriptCleanupService.basicCleanup("hello . world")
        XCTAssertEqual(result, "hello. world")
    }

    func testBasicCleanupSpaceBeforeExclamation() {
        let result = TranscriptCleanupService.basicCleanup("hello !")
        XCTAssertEqual(result, "hello!")
    }

    func testBasicCleanupSpaceBeforeQuestion() {
        let result = TranscriptCleanupService.basicCleanup("hello ?")
        XCTAssertEqual(result, "hello?")
    }

    func testBasicCleanupTrimsEdges() {
        let result = TranscriptCleanupService.basicCleanup("  hello  ")
        XCTAssertEqual(result, "hello")
    }

    func testBasicCleanupComplexText() {
        let input = "  hello ,  world .\r\n\n\n\nGoodbye\t !"
        let result = TranscriptCleanupService.basicCleanup(input)
        XCTAssertEqual(result, "hello, world.\n\nGoodbye!")
    }

    func testBasicCleanupEmptyAfterCleanup() {
        let result = TranscriptCleanupService.basicCleanup("   \n  \n  ")
        XCTAssertEqual(result, "")
    }

    // MARK: - cleanupEndpoint

    func testCleanupEndpointTransformAnalyzePath() {
        let url = TranscriptCleanupService.cleanupEndpoint(
            fromAnalyzeEndpoint: "http://localhost:3000/analyze")
        XCTAssertEqual(url?.absoluteString, "http://localhost:3000/cleanup")
    }

    func testCleanupEndpointRootPath() {
        let url = TranscriptCleanupService.cleanupEndpoint(
            fromAnalyzeEndpoint: "http://localhost:3000/")
        XCTAssertEqual(url?.absoluteString, "http://localhost:3000/cleanup")
    }

    func testCleanupEndpointNoTrailingSlash() {
        let url = TranscriptCleanupService.cleanupEndpoint(
            fromAnalyzeEndpoint: "http://localhost:3000")
        XCTAssertEqual(url?.absoluteString, "http://localhost:3000/cleanup")
    }

    func testCleanupEndpointAlreadyCleanup() {
        let url = TranscriptCleanupService.cleanupEndpoint(
            fromAnalyzeEndpoint: "http://localhost:3000/cleanup")
        XCTAssertEqual(url?.absoluteString, "http://localhost:3000/cleanup")
    }

    func testCleanupEndpointNestedAnalyzePath() {
        let url = TranscriptCleanupService.cleanupEndpoint(
            fromAnalyzeEndpoint: "http://localhost:3000/api/v1/analyze")
        XCTAssertEqual(url?.absoluteString, "http://localhost:3000/api/v1/cleanup")
    }

    func testCleanupEndpointCustomPath() {
        let url = TranscriptCleanupService.cleanupEndpoint(
            fromAnalyzeEndpoint: "http://localhost:3000/api")
        XCTAssertEqual(url?.absoluteString, "http://localhost:3000/api/cleanup")
    }

    // MARK: - suggestCleanup

    func testSuggestCleanupEmptyTextReturnsEmpty() async {
        let result = await TranscriptCleanupService.suggestCleanup(
            text: "", useCopilot: false, copilotAnalyzeEndpoint: ""
        )
        XCTAssertEqual(result.cleanedText, "")
        XCTAssertEqual(result.source, "empty")
    }

    func testSuggestCleanupLocalFallback() async {
        let result = await TranscriptCleanupService.suggestCleanup(
            text: "hello ,  world .", useCopilot: false, copilotAnalyzeEndpoint: ""
        )
        XCTAssertEqual(result.cleanedText, "hello, world.")
        XCTAssertEqual(result.source, "local")
        XCTAssertNil(result.error)
    }

    func testSuggestCleanupWhitespaceOnlyReturnsEmpty() async {
        let result = await TranscriptCleanupService.suggestCleanup(
            text: "   \n\t  ", useCopilot: false, copilotAnalyzeEndpoint: ""
        )
        XCTAssertEqual(result.cleanedText, "")
        XCTAssertEqual(result.source, "empty")
    }

    // MARK: - TranscriptCleanupResult

    func testCleanupResultEquality() {
        let a = TranscriptCleanupResult(cleanedText: "hello", source: "local")
        let b = TranscriptCleanupResult(cleanedText: "hello", source: "local")
        XCTAssertEqual(a, b)
    }

    func testCleanupResultInequalityOnText() {
        let a = TranscriptCleanupResult(cleanedText: "hello", source: "local")
        let b = TranscriptCleanupResult(cleanedText: "world", source: "local")
        XCTAssertNotEqual(a, b)
    }

    func testCleanupResultDefaultError() {
        let result = TranscriptCleanupResult(cleanedText: "text", source: "local")
        XCTAssertNil(result.error)
    }
}
