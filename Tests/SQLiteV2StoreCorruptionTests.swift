import Foundation
import XCTest

@testable import WhisperShared

final class SQLiteV2StoreCorruptionTests: XCTestCase {
    private var tempDir: URL!
    private var store: SQLiteV2Store!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteV2StoreCorruptionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SQLiteV2Store.shared(baseURL: tempDir)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    func testMalformedHistoryIdentityThrowsTypedCorruptionError() throws {
        let entry = DictationHistoryEntry(
            text: "valid",
            timestamp: Date(timeIntervalSince1970: 1),
            durationSeconds: 1,
            model: "base.en",
            outputMethod: "type"
        )
        try store.replaceHistoryEntries([entry])
        try executeSQL("UPDATE dictation_history SET id = 'malformed-id' WHERE sort_order = 0")

        assertCorruption(try store.fetchHistoryEntries(), table: "dictation_history", row: "malformed-id", column: "id", reason: .invalidUUID)
    }

    func testMalformedIdentityInEveryRowDecoderThrowsTypedCorruptionError() throws {
        let memo = VoiceMemo(
            title: "Memo",
            createdAt: Date(timeIntervalSince1970: 10),
            durationSeconds: 1,
            audioFileName: "memo.m4a"
        )
        let term = VocabTerm(term: "term", category: "Custom")
        let correction = CorrectionRecord(originalText: "before", correctedText: "after")

        try store.replaceHistoryEntries([
            DictationHistoryEntry(
                text: "history",
                timestamp: Date(timeIntervalSince1970: 10),
                durationSeconds: 1,
                model: "base.en",
                outputMethod: "type"
            )
        ])
        try store.replaceMemos([memo])
        try store.replaceVocabularyTerms([term])
        try store.replaceCorrections([correction])
        try executeSQL("UPDATE dictation_history SET id = 'bad-history-id' WHERE sort_order = 0")
        try executeSQL("UPDATE voice_memos SET id = 'bad-memo-id' WHERE sort_order = 0")
        try executeSQL("UPDATE vocabulary_terms SET id = 'bad-term-id' WHERE sort_order = 0")
        try executeSQL("UPDATE corrections SET id = 'bad-correction-id' WHERE sort_order = 0")

        assertCorruption(try store.fetchHistoryEntries(), table: "dictation_history", row: "bad-history-id", column: "id", reason: .invalidUUID)
        assertCorruption(try store.fetchMemos(), table: "voice_memos", row: "bad-memo-id", column: "id", reason: .invalidUUID)
        assertCorruption(try store.fetchVocabularyTerms(), table: "vocabulary_terms", row: "bad-term-id", column: "id", reason: .invalidUUID)
        assertCorruption(try store.fetchCorrections(), table: "corrections", row: "bad-correction-id", column: "id", reason: .invalidUUID)
    }

    func testMalformedTranscriptWordsThrowTypedCorruptionErrorWithoutTranscriptContents() throws {
        let sensitiveTranscript = "private transcript payload"
        let memo = VoiceMemo(
            title: "Memo",
            createdAt: Date(timeIntervalSince1970: 2),
            durationSeconds: 1,
            audioFileName: "memo.m4a",
            transcript: sensitiveTranscript,
            transcriptWords: [TranscriptWord(word: "valid", start: 0, end: 1)]
        )
        try store.replaceMemos([memo])
        try executeSQL("UPDATE voice_memos SET transcript_words_json = '{malformed-json' WHERE sort_order = 0")

        do {
            _ = try store.fetchMemos()
            XCTFail("Expected malformed transcript words to throw")
        } catch let error as SQLiteV2StoreError {
            guard case let .rowDecodingCorruption(table, row, column, reason) = error else {
                return XCTFail("Unexpected SQLite error: \(error)")
            }
            XCTAssertEqual(table, "voice_memos")
            XCTAssertEqual(row, memo.id.uuidString)
            XCTAssertEqual(column, "transcript_words_json")
            XCTAssertEqual(reason, .invalidSerializedData)
            XCTAssertFalse(error.localizedDescription.contains(sensitiveTranscript))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidLegacyNilTranscriptWordsRemainNil() throws {
        let memo = VoiceMemo(
            title: "Legacy memo",
            createdAt: Date(timeIntervalSince1970: 3),
            durationSeconds: 1,
            audioFileName: "legacy.m4a",
            transcript: "legacy",
            transcriptWords: nil
        )
        try store.replaceMemos([memo])

        let loaded = try store.fetchMemos()

        XCTAssertEqual(loaded.map(\.transcriptWords), [nil])
    }

    func testMixedValidAndCorruptRowsThrowInsteadOfReturningPartialResults() throws {
        let valid = DictationHistoryEntry(
            text: "valid",
            timestamp: Date(timeIntervalSince1970: 4),
            durationSeconds: 1,
            model: "base.en",
            outputMethod: "type"
        )
        let corrupt = DictationHistoryEntry(
            text: "corrupt",
            timestamp: Date(timeIntervalSince1970: 5),
            durationSeconds: 1,
            model: "base.en",
            outputMethod: "type"
        )
        try store.replaceHistoryEntries([valid, corrupt])
        try executeSQL("UPDATE dictation_history SET id = 'corrupt-row-id' WHERE sort_order = 1")

        assertCorruption(try store.fetchHistoryEntries(), table: "dictation_history", row: "corrupt-row-id", column: "id", reason: .invalidUUID)
    }

    private func assertCorruption<T>(
        _ result: @autoclosure () throws -> T,
        table: String,
        row: String,
        column: String,
        reason: SQLiteV2StoreError.CorruptionReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try result()
            XCTFail("Expected row corruption", file: file, line: line)
        } catch let error as SQLiteV2StoreError {
            XCTAssertEqual(error, .rowDecodingCorruption(table: table, row: row, column: column, reason: reason), file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func executeSQL(_ sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [store.paths.databaseURL.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "sqlite3 update failed")
    }
}
