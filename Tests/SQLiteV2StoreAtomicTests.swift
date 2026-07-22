import Foundation
import XCTest

@testable import WhisperShared

final class SQLiteV2StoreAtomicTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteV2StoreAtomicTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    func testIndependentStoresApplyOrderedBatchUpsertsAndDeletesWithoutReplacingUnrelatedRows() throws {
        let firstStore = SQLiteV2Store(baseURL: tempDir)
        let secondStore = SQLiteV2Store(baseURL: tempDir)

        let first = VocabTerm(id: UUID(), term: "first", category: "Custom")
        let second = VocabTerm(id: UUID(), term: "second", category: "Custom")
        let third = VocabTerm(id: UUID(), term: "third", category: "Custom")

        try firstStore.upsertVocabularyTerms([first, second])
        try secondStore.upsertVocabularyTerm(
            VocabTerm(id: first.id, term: "first updated", category: first.category)
        )
        try firstStore.upsertVocabularyTerm(third)
        try secondStore.deleteVocabularyTerms(ids: [second.id])

        let terms = try firstStore.fetchVocabularyTerms()
        XCTAssertEqual(terms.map(\.id), [first.id, third.id])
        XCTAssertEqual(terms.map(\.term), ["first updated", "third"])
    }

    func testIndependentRepositoriesConcurrentWritesRetainEveryRow() async throws {
        let firstRepository = SQLiteRepositoryStore(baseURL: tempDir)
        let secondRepository = SQLiteRepositoryStore(baseURL: tempDir)
        let entries = (0..<40).map { index in
            DictationHistoryEntry(
                id: UUID(),
                text: "entry-\(index)",
                timestamp: Date(timeIntervalSince1970: Double(index)),
                durationSeconds: 1,
                model: "base.en",
                outputMethod: "type"
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        try await firstRepository.saveHistoryEntry(entry)
                    } else {
                        try await secondRepository.saveHistoryEntry(entry)
                    }
                }
            }
            try await group.waitForAll()
        }

        let stored = try await firstRepository.fetchAllHistory()
        XCTAssertEqual(stored.count, entries.count)
        XCTAssertEqual(Set(stored.map(\.id)), Set(entries.map(\.id)))
        XCTAssertEqual(stored.map(\.timestamp), entries.map(\.timestamp).sorted(by: >))
    }

    func testRowOperationsCoverHistoryMemosTermsAndCorrections() throws {
        let firstStore = SQLiteV2Store(baseURL: tempDir)
        let secondStore = SQLiteV2Store(baseURL: tempDir)

        let history = DictationHistoryEntry(
            text: "history",
            timestamp: Date(timeIntervalSince1970: 1),
            durationSeconds: 1,
            model: "base.en",
            outputMethod: "type"
        )
        let memo = VoiceMemo(
            title: "memo",
            createdAt: Date(timeIntervalSince1970: 2),
            durationSeconds: 2,
            audioFileName: "memo.m4a"
        )
        let term = VocabTerm(term: "term", category: "Custom")
        let correction = CorrectionRecord(originalText: "before", correctedText: "after")

        try firstStore.upsertHistoryEntry(history)
        try firstStore.upsertMemo(memo)
        try firstStore.upsertVocabularyTerm(term)
        try firstStore.upsertCorrection(correction)

        try secondStore.deleteHistoryEntry(id: history.id)
        try secondStore.deleteMemo(id: memo.id)
        try secondStore.deleteVocabularyTerm(id: term.id)
        try secondStore.deleteCorrection(id: correction.id)

        XCTAssertTrue(try firstStore.fetchHistoryEntries().isEmpty)
        XCTAssertTrue(try firstStore.fetchMemos().isEmpty)
        XCTAssertTrue(try firstStore.fetchVocabularyTerms().isEmpty)
        XCTAssertTrue(try firstStore.fetchCorrections().isEmpty)
    }
}
