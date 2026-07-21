import Foundation
import XCTest

@testable import WhisperShared

final class SQLiteRepositoryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRepositoryCRUDRoundTripsAcrossDomains() async throws {
        let repository = SQLiteRepositoryStore(baseURL: tempDir)

        let historyEntry = DictationHistoryEntry(
            text: "hello repo",
            timestamp: Date(timeIntervalSince1970: 1234),
            durationSeconds: 1.2,
            model: "base.en",
            outputMethod: "paste"
        )
        try await repository.saveHistoryEntry(historyEntry)

        let memo = VoiceMemo(
            title: "Planning",
            createdAt: Date(timeIntervalSince1970: 2000),
            durationSeconds: 32,
            audioFileName: "memo.m4a",
            transcript: "memo text",
            transcriptWords: [TranscriptWord(word: "memo", start: 0, end: 0.5)],
            isTranscribing: false,
            autoTranscribe: true
        )
        try await repository.saveMemo(memo)

        let term = VocabTerm(term: "WhisperKit", category: "Software Engineering")
        try await repository.saveTerm(term)

        let correction = CorrectionRecord(
            originalText: "whsiper",
            correctedText: "whisper",
            createdAt: Date(timeIntervalSince1970: 3000),
            appliedCount: 2
        )
        try await repository.saveCorrection(correction)

        let history = try await repository.fetchAllHistory()
        XCTAssertEqual(history, [historyEntry])

        let memos = try await repository.fetchAllMemos()
        XCTAssertEqual(memos, [memo])

        let terms = try await repository.fetchAllTerms()
        XCTAssertEqual(terms, [term])

        let corrections = try await repository.fetchAllCorrections()
        XCTAssertEqual(corrections, [correction])

        try await repository.deleteHistoryEntry(id: historyEntry.id)
        try await repository.deleteMemo(id: memo.id)
        try await repository.deleteTerm(id: term.id)
        try await repository.deleteCorrection(id: correction.id)

        let emptyHistory = try await repository.fetchAllHistory()
        let emptyMemos = try await repository.fetchAllMemos()
        let emptyTerms = try await repository.fetchAllTerms()
        let emptyCorrections = try await repository.fetchAllCorrections()

        XCTAssertTrue(emptyHistory.isEmpty)
        XCTAssertTrue(emptyMemos.isEmpty)
        XCTAssertTrue(emptyTerms.isEmpty)
        XCTAssertTrue(emptyCorrections.isEmpty)
    }

    func testLegacyJSONImportPopulatesSQLiteAndPreservesSourceFiles() async throws {
        let appDir = tempDir.appendingPathComponent("Whisper", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        let history = [
            DictationHistoryEntry(
                text: "legacy history",
                timestamp: Date(timeIntervalSince1970: 100),
                durationSeconds: 3,
                model: "base.en",
                outputMethod: "type"
            )
        ]
        let memo = [
            VoiceMemo(
                title: "Legacy Memo",
                createdAt: Date(timeIntervalSince1970: 200),
                durationSeconds: 15,
                audioFileName: "legacy.m4a",
                transcript: "legacy transcript",
                transcriptWords: [TranscriptWord(word: "legacy", start: 0, end: 0.6)],
                isTranscribing: false,
                autoTranscribe: true
            )
        ]
        let terms = [
            VocabTerm(term: "Codex", category: "Custom")
        ]
        let corrections = [
            LegacyCorrectionFixture(
                original: "teh",
                corrected: "the",
                timestamp: Date(timeIntervalSince1970: 400),
                appliedCount: 1
            )
        ]

        try JSONEncoder().encode(history).write(
            to: appDir.appendingPathComponent("dictation-history.json")
        )
        try JSONEncoder().encode(memo).write(
            to: appDir.appendingPathComponent("voice-memos.json")
        )
        try JSONEncoder().encode(terms).write(
            to: appDir.appendingPathComponent("vocabulary.json")
        )
        try JSONEncoder().encode(corrections).write(
            to: appDir.appendingPathComponent("corrections.json")
        )

        let repository = SQLiteRepositoryStore(baseURL: tempDir)

        let importedHistory = try await repository.fetchAllHistory()
        let importedMemos = try await repository.fetchAllMemos()
        let importedTerms = try await repository.fetchAllTerms()
        let importedCorrections = try await repository.fetchAllCorrections()

        XCTAssertEqual(importedHistory.map(\.text), ["legacy history"])
        XCTAssertEqual(importedMemos.map(\.title), ["Legacy Memo"])
        XCTAssertEqual(importedTerms.map(\.term), ["Codex"])
        XCTAssertEqual(importedCorrections.map(\.correctedText), ["the"])

        let migration = try await repository.loadMigrationState()
        XCTAssertEqual(Set(migration.importedSources), Set(LegacyImportSource.allCases))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appDir.appendingPathComponent("dictation-history.json").path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appDir.appendingPathComponent("voice-memos.json").path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appDir.appendingPathComponent("vocabulary.json").path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: appDir.appendingPathComponent("corrections.json").path)
        )
    }

    func testMigrationStateRoundTrips() async throws {
        let repository = SQLiteRepositoryStore(baseURL: tempDir)
        let snapshot = MigrationStateSnapshot(
            importedSources: [.dictationHistoryJSON, .voiceMemosJSON],
            parityVerifiedSources: [.dictationHistoryJSON],
            lastMigrationAt: Date(timeIntervalSince1970: 500)
        )

        try await repository.saveMigrationState(snapshot)
        let loaded = try await repository.loadMigrationState()

        XCTAssertEqual(loaded, snapshot)
    }
}

private struct LegacyCorrectionFixture: Codable {
    let original: String
    let corrected: String
    let timestamp: Date
    let appliedCount: Int
}
