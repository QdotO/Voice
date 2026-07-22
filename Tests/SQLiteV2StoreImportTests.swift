import Foundation
import XCTest

@testable import WhisperShared

final class SQLiteV2StoreImportTests: XCTestCase {
    private var tempDir: URL!
    private var store: SQLiteV2Store!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteV2StoreImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SQLiteV2Store.shared(baseURL: tempDir)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    func testMissingSourceRecordsMissingAndStaysRetryable() throws {
        let initialReport = try store.loadLegacyImportReport()

        XCTAssertEqual(
            initialReport.outcomes[.dictationHistoryJSON],
            .missing
        )
        XCTAssertEqual(initialReport.overallOutcome, .missing)
        XCTAssertFalse(try store.loadMigrationState().importedSources.contains(.dictationHistoryJSON))

        try writeJSON(
            [
                DictationHistoryEntry(
                    text: "appeared later",
                    timestamp: Date(timeIntervalSince1970: 1),
                    durationSeconds: 1,
                    model: "base.en",
                    outputMethod: "type"
                )
            ],
            to: .dictationHistoryJSON
        )
        try store.importLegacyJSONIfNeeded()

        XCTAssertEqual(
            try store.loadLegacyImportReport().outcomes[.dictationHistoryJSON],
            .imported(count: 1)
        )
        XCTAssertTrue(try store.loadMigrationState().importedSources.contains(.dictationHistoryJSON))
    }

    func testMalformedSourceRecordsMalformedWithoutPreventingOtherSources() throws {
        try writeRaw("{malformed", to: .voiceMemosJSON)

        try store.importLegacyJSONIfNeeded()

        XCTAssertEqual(
            try store.loadLegacyImportReport().outcomes[.voiceMemosJSON],
            .malformed
        )
    }

    func testEmptyValidSourceRecordsImportedZero() throws {
        try writeJSON([VocabTerm](), to: .vocabularyJSON)

        try store.importLegacyJSONIfNeeded()

        let report = try store.loadLegacyImportReport()
        XCTAssertEqual(report.outcomes[.vocabularyJSON], .imported(count: 0))
        XCTAssertTrue(try store.loadMigrationState().importedSources.contains(.vocabularyJSON))
        XCTAssertTrue(try store.fetchVocabularyTerms().isEmpty)
    }

    func testNonemptyDestinationRecordsSkippedNonempty() throws {
        try store.replaceHistoryEntries([
            DictationHistoryEntry(
                text: "existing",
                timestamp: Date(timeIntervalSince1970: 1),
                durationSeconds: 1,
                model: "base.en",
                outputMethod: "type"
            )
        ])
        try writeJSON(
            [
                DictationHistoryEntry(
                    text: "legacy",
                    timestamp: Date(timeIntervalSince1970: 2),
                    durationSeconds: 1,
                    model: "base.en",
                    outputMethod: "type"
                )
            ],
            to: .dictationHistoryJSON
        )

        try store.importLegacyJSONIfNeeded()

        XCTAssertEqual(
            try store.loadLegacyImportReport().outcomes[.dictationHistoryJSON],
            .skippedNonempty
        )
        XCTAssertEqual(try store.fetchHistoryEntries().map(\.text), ["existing"])
    }

    func testSuccessfulImportIsIdempotentAndPreservesCount() throws {
        try writeJSON(
            [
                DictationHistoryEntry(
                    text: "once",
                    timestamp: Date(timeIntervalSince1970: 1),
                    durationSeconds: 1,
                    model: "base.en",
                    outputMethod: "type"
                )
            ],
            to: .dictationHistoryJSON
        )

        try store.importLegacyJSONIfNeeded()
        let firstState = try store.loadMigrationState()
        try store.importLegacyJSONIfNeeded()

        XCTAssertEqual(
            try store.loadLegacyImportReport().outcomes[.dictationHistoryJSON],
            .imported(count: 1)
        )
        XCTAssertEqual(try store.fetchHistoryEntries().map(\.text), ["once"])
        XCTAssertEqual(try store.loadMigrationState().importedSources, firstState.importedSources)
    }

    func testPartialMultiSourceFailureRecordsEachOutcomeAndAggregateFailure() throws {
        try writeJSON(
            [
                DictationHistoryEntry(
                    text: "valid history",
                    timestamp: Date(timeIntervalSince1970: 1),
                    durationSeconds: 1,
                    model: "base.en",
                    outputMethod: "type"
                )
            ],
            to: .dictationHistoryJSON
        )
        try writeRaw("{malformed", to: .voiceMemosJSON)

        try store.importLegacyJSONIfNeeded()

        let report = try store.loadLegacyImportReport()
        XCTAssertEqual(report.outcomes[.dictationHistoryJSON], .imported(count: 1))
        XCTAssertEqual(report.outcomes[.voiceMemosJSON], .malformed)
        XCTAssertEqual(report.overallOutcome, .partialFailure)

        let importedSources = Set(try store.loadMigrationState().importedSources)
        XCTAssertTrue(importedSources.contains(.dictationHistoryJSON))
        XCTAssertTrue(importedSources.contains(.voiceMemosJSON))
        XCTAssertFalse(importedSources.contains(.vocabularyJSON))
        XCTAssertEqual(try store.fetchHistoryEntries().map(\.text), ["valid history"])
    }

    private enum Source {
        case dictationHistoryJSON
        case voiceMemosJSON
        case vocabularyJSON
        case correctionsJSON

        var urlKey: KeyPath<WhisperPersistencePaths, URL> {
            switch self {
            case .dictationHistoryJSON: return \.dictationHistoryJSONURL
            case .voiceMemosJSON: return \.voiceMemosJSONURL
            case .vocabularyJSON: return \.vocabularyJSONURL
            case .correctionsJSON: return \.correctionsJSONURL
            }
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to source: Source) throws {
        try JSONEncoder().encode(value).write(to: store.paths[keyPath: source.urlKey])
    }

    private func writeRaw(_ value: String, to source: Source) throws {
        try Data(value.utf8).write(to: store.paths[keyPath: source.urlKey])
    }
}
