import XCTest
@testable import WhisperShared

final class HistoryDestructiveActionTests: XCTestCase {
    func testSingleTranscriptionCopy() {
        let action = HistoryDestructiveAction.deleteTranscriptions(ids: [UUID()])

        XCTAssertEqual(action.title, "Delete transcription?")
        XCTAssertEqual(
            action.message,
            "This removes this transcription from History. This cannot be undone."
        )
        XCTAssertEqual(action.confirmButtonTitle, "Delete")
    }

    func testSingleCorrectionCopy() {
        let action = HistoryDestructiveAction.deleteCorrections(ids: [UUID()])

        XCTAssertEqual(action.title, "Delete learned correction?")
        XCTAssertEqual(
            action.message,
            "Whisper will no longer apply this correction. This cannot be undone."
        )
        XCTAssertEqual(action.confirmButtonTitle, "Delete")
    }

    func testBulkCopyUsesCount() {
        XCTAssertEqual(
            HistoryDestructiveAction.clearHistory(count: 3).message,
            "This removes 3 transcriptions. This cannot be undone."
        )
        XCTAssertEqual(
            HistoryDestructiveAction.clearCorrections(count: 7).message,
            "This removes 7 learned corrections. This cannot be undone."
        )
        XCTAssertEqual(
            HistoryDestructiveAction.clearHistory(count: 3).title,
            "Clear all History?"
        )
        XCTAssertEqual(
            HistoryDestructiveAction.clearCorrections(count: 7).title,
            "Clear all Corrections?"
        )
    }

    func testActionsHaveStableDistinctIDs() {
        let id = UUID()

        XCTAssertNotEqual(
            HistoryDestructiveAction.deleteTranscriptions(ids: [id]).id,
            HistoryDestructiveAction.deleteCorrections(ids: [id]).id
        )
        XCTAssertNotEqual(
            HistoryDestructiveAction.clearHistory(count: 1).id,
            HistoryDestructiveAction.clearHistory(count: 2).id
        )
    }
}
