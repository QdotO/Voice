import Foundation
import GRDB
import OSLog

struct WhisperPersistencePaths {
    let baseURL: URL
    let appDirectory: URL
    let databaseURL: URL
    let voiceMemosDirectory: URL
    let dictationHistoryJSONURL: URL
    let voiceMemosJSONURL: URL
    let vocabularyJSONURL: URL
    let correctionsJSONURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL.resolvingSymlinksInPath().standardizedFileURL
        self.appDirectory = self.baseURL.appendingPathComponent("Whisper", isDirectory: true)
        self.databaseURL = appDirectory.appendingPathComponent("whisper-v2.sqlite")
        self.voiceMemosDirectory = appDirectory.appendingPathComponent(
            "voice-memos", isDirectory: true)
        self.dictationHistoryJSONURL = appDirectory.appendingPathComponent("dictation-history.json")
        self.voiceMemosJSONURL = appDirectory.appendingPathComponent("voice-memos.json")
        self.vocabularyJSONURL = appDirectory.appendingPathComponent("vocabulary.json")
        self.correctionsJSONURL = appDirectory.appendingPathComponent("corrections.json")
    }
}

public enum SQLiteV2StoreError: Error, Equatable, LocalizedError, Sendable {
    public enum CorruptionReason: String, Equatable, Sendable {
        case invalidUUID
        case invalidSerializedData
    }

    case rowDecodingCorruption(
        table: String,
        row: String,
        column: String,
        reason: CorruptionReason
    )

    public var table: String {
        switch self {
        case let .rowDecodingCorruption(table, _, _, _): return table
        }
    }

    public var row: String {
        switch self {
        case let .rowDecodingCorruption(_, row, _, _): return row
        }
    }

    public var column: String {
        switch self {
        case let .rowDecodingCorruption(_, _, column, _): return column
        }
    }

    public var reason: CorruptionReason {
        switch self {
        case let .rowDecodingCorruption(_, _, _, reason): return reason
        }
    }

    public var errorDescription: String? {
        "Corrupt row in \(table) (\(row)) column \(column): \(reason.rawValue)"
    }
}

enum LegacyImportOutcome: Codable, Equatable, Sendable {
    case missing
    case malformed
    case imported(count: Int)
    case skippedNonempty
    case partialFailure

    private enum CodingKeys: String, CodingKey {
        case kind
        case count
    }

    private enum Kind: String, Codable {
        case missing
        case malformed
        case imported
        case skippedNonempty
        case partialFailure
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .missing:
            self = .missing
        case .malformed:
            self = .malformed
        case .imported:
            self = .imported(count: try container.decode(Int.self, forKey: .count))
        case .skippedNonempty:
            self = .skippedNonempty
        case .partialFailure:
            self = .partialFailure
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .missing:
            try container.encode(Kind.missing, forKey: .kind)
        case .malformed:
            try container.encode(Kind.malformed, forKey: .kind)
        case let .imported(count):
            try container.encode(Kind.imported, forKey: .kind)
            try container.encode(count, forKey: .count)
        case .skippedNonempty:
            try container.encode(Kind.skippedNonempty, forKey: .kind)
        case .partialFailure:
            try container.encode(Kind.partialFailure, forKey: .kind)
        }
    }
}

struct LegacyImportReport: Codable, Equatable, Sendable {
    let outcomes: [LegacyImportSource: LegacyImportOutcome]
    let overallOutcome: LegacyImportOutcome
}

private struct LegacyImportStateEnvelope: Codable {
    let importedSources: [LegacyImportSource]
    let outcomes: [LegacyImportSource: LegacyImportOutcome]
}

/// Synchronously serializes all SQLite access through GRDB's `DatabaseQueue`.
/// Paths are immutable; no database handle escapes this type. `@unchecked Sendable`
/// records that GRDB owns synchronization for the queue's mutable connection state.
final class SQLiteV2Store: @unchecked Sendable {
    private static let logger = Logger(subsystem: "Whisper", category: "Persistence")
    private static let cache = SQLiteV2StoreCache()

    static func shared(baseURL: URL = SharedStorage.baseDirectory()) -> SQLiteV2Store {
        let normalized = baseURL.resolvingSymlinksInPath().standardizedFileURL
        return cache.store(for: normalized) {
            SQLiteV2Store(baseURL: normalized)
        }
    }

    let paths: WhisperPersistencePaths
    private let dbQueue: DatabaseQueue

    init(baseURL: URL) {
        self.paths = WhisperPersistencePaths(baseURL: baseURL)

        do {
            try FileManager.default.createDirectory(
                at: paths.appDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: paths.voiceMemosDirectory,
                withIntermediateDirectories: true
            )

            var databaseConfiguration = Configuration()
            databaseConfiguration.busyMode = .timeout(5)
            databaseConfiguration.journalMode = .wal
            dbQueue = try DatabaseQueue(
                path: paths.databaseURL.path,
                configuration: databaseConfiguration
            )
            try Self.makeMigrator().migrate(dbQueue)
            try importLegacyJSONIfNeeded()
        } catch {
            fatalError("Failed to initialize Whisper v2 persistence: \(error)")
        }
    }

    func fetchHistoryEntries() throws -> [DictationHistoryEntry] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, text, timestamp_seconds, duration_seconds, model, output_method
                    FROM dictation_history
                    ORDER BY sort_order ASC
                    """
            )
            .map { try Self.makeHistoryEntry(from: $0) }
        }
    }

    /// Upserts rows in input order. Existing rows keep their current position;
    /// new rows append after the current highest sort order.
    func upsertHistoryEntry(_ entry: DictationHistoryEntry) throws {
        try upsertHistoryEntries([entry])
    }

    func upsertHistoryEntries(_ entries: [DictationHistoryEntry]) throws {
        try writeTransaction { db in
            for entry in entries {
                try upsertHistoryEntry(entry, in: db)
            }
        }
    }

    /// Upserts one row and trims oldest rows in one transaction.
    func upsertHistoryEntryAndTrim(_ entry: DictationHistoryEntry, maxEntries: Int) throws {
        try writeTransaction { db in
            try upsertHistoryEntry(entry, in: db)

            guard maxEntries >= 0 else { return }
            let overflowRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id
                    FROM dictation_history
                    ORDER BY sort_order DESC
                    LIMIT -1 OFFSET ?
                    """,
                arguments: [maxEntries]
            )
            for row in overflowRows {
                try db.execute(
                    sql: "DELETE FROM dictation_history WHERE id = ?",
                    arguments: [row["id"] as String]
                )
            }
        }
    }

    private func upsertHistoryEntry(_ entry: DictationHistoryEntry, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO dictation_history (
                    id, sort_order, text, timestamp_seconds, duration_seconds, model, output_method
                ) VALUES (?, COALESCE((SELECT MAX(sort_order) + 1 FROM dictation_history), 0), ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    text = excluded.text,
                    timestamp_seconds = excluded.timestamp_seconds,
                    duration_seconds = excluded.duration_seconds,
                    model = excluded.model,
                    output_method = excluded.output_method
                """,
            arguments: [
                entry.id.uuidString,
                entry.text,
                entry.timestamp.timeIntervalSince1970,
                entry.durationSeconds,
                entry.model,
                entry.outputMethod,
            ]
        )
    }

    func deleteHistoryEntry(id: UUID) throws {
        try deleteHistoryEntries(ids: [id])
    }

    func deleteHistoryEntries(ids: [UUID]) throws {
        try writeTransaction { db in
            for id in ids {
                try db.execute(
                    sql: "DELETE FROM dictation_history WHERE id = ?",
                    arguments: [id.uuidString]
                )
            }
        }
    }

    func deleteAllHistory() throws {
        try writeTransaction { db in
            try db.execute(sql: "DELETE FROM dictation_history")
        }
    }

    func replaceHistoryEntries(_ entries: [DictationHistoryEntry]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM dictation_history")
            for (index, entry) in entries.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO dictation_history (
                            id, sort_order, text, timestamp_seconds, duration_seconds, model, output_method
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        entry.id.uuidString,
                        index,
                        entry.text,
                        entry.timestamp.timeIntervalSince1970,
                        entry.durationSeconds,
                        entry.model,
                        entry.outputMethod,
                    ]
                )
            }
        }
    }

    func fetchMemos() throws -> [VoiceMemo] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, title, created_at_seconds, duration_seconds, audio_file_name,
                           transcript, transcript_words_json, is_transcribing, auto_transcribe
                    FROM voice_memos
                    ORDER BY sort_order ASC
                    """
            )
            .map { try Self.makeVoiceMemo(from: $0) }
        }
    }

    /// Upserts rows in input order. Existing rows keep their current position;
    /// new rows append after the current highest sort order.
    func upsertMemo(_ memo: VoiceMemo) throws {
        try upsertMemos([memo])
    }

    func upsertMemos(_ memos: [VoiceMemo]) throws {
        try writeTransaction { db in
            for memo in memos {
                try upsertMemo(memo, in: db)
            }
        }
    }

    /// Updates one current row and upserts it in the same SQLite write transaction.
    /// Returns nil when no row exists for id.
    func updateMemo(id: UUID, block: (inout VoiceMemo) -> Void) throws -> VoiceMemo? {
        try writeTransaction { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT id, title, created_at_seconds, duration_seconds, audio_file_name,
                               transcript, transcript_words_json, is_transcribing, auto_transcribe
                        FROM voice_memos
                        WHERE id = ?
                        """,
                    arguments: [id.uuidString]
                )
            else {
                return nil
            }

            var memo = try Self.makeVoiceMemo(from: row)
            block(&memo)
            try upsertMemo(memo, in: db)
            return memo
        }
    }

    private func upsertMemo(_ memo: VoiceMemo, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO voice_memos (
                    id, sort_order, title, created_at_seconds, duration_seconds,
                    audio_file_name, transcript, transcript_words_json,
                    is_transcribing, auto_transcribe
                ) VALUES (?, COALESCE((SELECT MAX(sort_order) + 1 FROM voice_memos), 0), ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    created_at_seconds = excluded.created_at_seconds,
                    duration_seconds = excluded.duration_seconds,
                    audio_file_name = excluded.audio_file_name,
                    transcript = excluded.transcript,
                    transcript_words_json = excluded.transcript_words_json,
                    is_transcribing = excluded.is_transcribing,
                    auto_transcribe = excluded.auto_transcribe
                """,
            arguments: [
                memo.id.uuidString,
                memo.title,
                memo.createdAt.timeIntervalSince1970,
                memo.durationSeconds,
                memo.audioFileName,
                memo.transcript,
                try Self.encodeJSONString(memo.transcriptWords),
                memo.isTranscribing,
                memo.autoTranscribe,
            ]
        )
    }

    func deleteMemo(id: UUID) throws {
        try deleteMemos(ids: [id])
    }

    func deleteMemos(ids: [UUID]) throws {
        try writeTransaction { db in
            for id in ids {
                try db.execute(
                    sql: "DELETE FROM voice_memos WHERE id = ?",
                    arguments: [id.uuidString]
                )
            }
        }
    }

    func replaceMemos(_ memos: [VoiceMemo]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM voice_memos")
            for (index, memo) in memos.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO voice_memos (
                            id, sort_order, title, created_at_seconds, duration_seconds,
                            audio_file_name, transcript, transcript_words_json,
                            is_transcribing, auto_transcribe
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        memo.id.uuidString,
                        index,
                        memo.title,
                        memo.createdAt.timeIntervalSince1970,
                        memo.durationSeconds,
                        memo.audioFileName,
                        memo.transcript,
                        try Self.encodeJSONString(memo.transcriptWords),
                        memo.isTranscribing,
                        memo.autoTranscribe,
                    ]
                )
            }
        }
    }

    func fetchVocabularyTerms() throws -> [VocabTerm] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, term, category, enabled
                    FROM vocabulary_terms
                    ORDER BY sort_order ASC
                    """
            )
            .map { try Self.makeVocabTerm(from: $0) }
        }
    }

    /// Upserts rows in input order. Existing rows keep their current position;
    /// new rows append after the current highest sort order.
    func upsertVocabularyTerm(_ term: VocabTerm) throws {
        try upsertVocabularyTerms([term])
    }

    /// Inserts term only when no case-insensitive equivalent exists.
    /// Duplicate check and insert share one write statement and transaction.
    func insertVocabularyTermIfAbsent(term: String, category: String) throws -> VocabTerm? {
        let candidate = VocabTerm(term: term, category: category)
        return try writeTransaction { db in
            try db.execute(
                sql: """
                    INSERT INTO vocabulary_terms (
                        id, sort_order, term, category, enabled
                    )
                    SELECT ?, COALESCE((SELECT MAX(sort_order) + 1 FROM vocabulary_terms), 0), ?, ?, ?
                    WHERE NOT EXISTS (
                        SELECT 1 FROM vocabulary_terms WHERE term = ? COLLATE NOCASE
                    )
                    """,
                arguments: [
                    candidate.id.uuidString,
                    candidate.term,
                    candidate.category,
                    candidate.enabled,
                    candidate.term,
                ]
            )
            return db.changesCount == 1 ? candidate : nil
        }
    }

    func toggleVocabularyTerm(id: UUID) throws -> Bool {
        try writeTransaction { db in
            try db.execute(
                sql: "UPDATE vocabulary_terms SET enabled = NOT enabled WHERE id = ?",
                arguments: [id.uuidString]
            )
            return db.changesCount == 1
        }
    }

    func setVocabularyTermsEnabled(_ enabled: Bool, ids: Set<UUID>) throws -> Bool {
        guard !ids.isEmpty else { return false }

        return try writeTransaction { db in
            var didChange = false
            for id in ids {
                try db.execute(
                    sql: "UPDATE vocabulary_terms SET enabled = ? WHERE id = ? AND enabled != ?",
                    arguments: [enabled, id.uuidString, enabled]
                )
                didChange = didChange || db.changesCount == 1
            }
            return didChange
        }
    }

    func setVocabularyCategoryEnabled(_ enabled: Bool, category: String) throws -> Bool {
        try writeTransaction { db in
            try db.execute(
                sql: "UPDATE vocabulary_terms SET enabled = ? WHERE category = ? AND enabled != ?",
                arguments: [enabled, category, enabled]
            )
            return db.changesCount > 0
        }
    }

    func upsertVocabularyTerms(_ terms: [VocabTerm]) throws {
        try writeTransaction { db in
            for term in terms {
                try db.execute(
                    sql: """
                        INSERT INTO vocabulary_terms (
                            id, sort_order, term, category, enabled
                        ) VALUES (?, COALESCE((SELECT MAX(sort_order) + 1 FROM vocabulary_terms), 0), ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            term = excluded.term,
                            category = excluded.category,
                            enabled = excluded.enabled
                        """,
                    arguments: [
                        term.id.uuidString,
                        term.term,
                        term.category,
                        term.enabled,
                    ]
                )
            }
        }
    }

    func deleteVocabularyTerm(id: UUID) throws {
        try deleteVocabularyTerms(ids: [id])
    }

    func deleteVocabularyTerms(ids: [UUID]) throws {
        try writeTransaction { db in
            for id in ids {
                try db.execute(
                    sql: "DELETE FROM vocabulary_terms WHERE id = ?",
                    arguments: [id.uuidString]
                )
            }
        }
    }

    func replaceVocabularyTerms(_ terms: [VocabTerm]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM vocabulary_terms")
            for (index, term) in terms.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO vocabulary_terms (
                            id, sort_order, term, category, enabled
                        ) VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        term.id.uuidString,
                        index,
                        term.term,
                        term.category,
                        term.enabled,
                    ]
                )
            }
        }
    }

    /// Replaces all vocabulary rows in one transaction for user-requested reset.
    func resetVocabularyTerms(_ terms: [VocabTerm]) throws {
        try writeTransaction { db in
            try db.execute(sql: "DELETE FROM vocabulary_terms")
            for (index, term) in terms.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO vocabulary_terms (
                            id, sort_order, term, category, enabled
                        ) VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        term.id.uuidString,
                        index,
                        term.term,
                        term.category,
                        term.enabled,
                    ]
                )
            }
        }
    }

    func fetchCorrections() throws -> [CorrectionRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, original_text, corrected_text, created_at_seconds, applied_count
                    FROM corrections
                    ORDER BY sort_order ASC
                    """
            )
            .map { try Self.makeCorrectionRecord(from: $0) }
        }
    }

    /// Upserts rows in input order. Existing rows keep their current position;
    /// new rows append after the current highest sort order.
    func upsertCorrection(_ correction: CorrectionRecord) throws {
        try upsertCorrections([correction])
    }

    func upsertCorrections(_ corrections: [CorrectionRecord]) throws {
        try writeTransaction { db in
            for correction in corrections {
                try upsertCorrection(correction, in: db)
            }
        }
    }

    /// Finds correction by case-insensitive original, updates or inserts it,
    /// and trims oldest rows as one transaction.
    func learnCorrectionAndTrim(
        _ correction: CorrectionRecord,
        maxCorrections: Int
    ) throws -> Bool {
        try writeTransaction { db in
            let existing = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, original_text, corrected_text, created_at_seconds, applied_count
                    FROM corrections
                    ORDER BY sort_order ASC
                    """
            )
            .map { try Self.makeCorrectionRecord(from: $0) }
            .first { $0.originalText.lowercased() == correction.originalText.lowercased() }

            if let existing {
                guard existing.correctedText != correction.correctedText else { return false }
                try upsertCorrection(
                    CorrectionRecord(
                        id: existing.id,
                        originalText: correction.originalText,
                        correctedText: correction.correctedText,
                        createdAt: correction.createdAt,
                        appliedCount: correction.appliedCount
                    ),
                    in: db
                )
            } else {
                try upsertCorrection(correction, in: db)
            }

            guard maxCorrections >= 0 else { return true }
            let overflowRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id
                    FROM corrections
                    ORDER BY sort_order DESC
                    LIMIT -1 OFFSET ?
                    """,
                arguments: [maxCorrections]
            )
            for row in overflowRows {
                try db.execute(
                    sql: "DELETE FROM corrections WHERE id = ?",
                    arguments: [row["id"] as String]
                )
            }
            return true
        }
    }

    @discardableResult
    func deleteCorrection(id: UUID) throws -> Bool {
        try deleteCorrections(ids: [id])
    }

    @discardableResult
    func deleteCorrections(ids: [UUID]) throws -> Bool {
        try writeTransaction { db in
            var didChange = false
            for id in ids {
                try db.execute(
                    sql: "DELETE FROM corrections WHERE id = ?",
                    arguments: [id.uuidString]
                )
                didChange = didChange || db.changesCount == 1
            }
            return didChange
        }
    }

    @discardableResult
    func deleteAllCorrections() throws -> Bool {
        try writeTransaction { db in
            try db.execute(sql: "DELETE FROM corrections")
            return db.changesCount > 0
        }
    }

    private func upsertCorrection(_ correction: CorrectionRecord, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO corrections (
                    id, sort_order, original_text, corrected_text, created_at_seconds, applied_count
                ) VALUES (?, COALESCE((SELECT MAX(sort_order) + 1 FROM corrections), 0), ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    original_text = excluded.original_text,
                    corrected_text = excluded.corrected_text,
                    created_at_seconds = excluded.created_at_seconds,
                    applied_count = excluded.applied_count
                """,
            arguments: [
                correction.id.uuidString,
                correction.originalText,
                correction.correctedText,
                correction.createdAt.timeIntervalSince1970,
                correction.appliedCount,
            ]
        )
    }

    func replaceCorrections(_ corrections: [CorrectionRecord]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM corrections")
            for (index, correction) in corrections.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO corrections (
                            id, sort_order, original_text, corrected_text, created_at_seconds, applied_count
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        correction.id.uuidString,
                        index,
                        correction.originalText,
                        correction.correctedText,
                        correction.createdAt.timeIntervalSince1970,
                        correction.appliedCount,
                    ]
                )
            }
        }
    }

    private func writeTransaction<Result>(_ updates: (Database) throws -> Result) throws -> Result {
        // DatabaseQueue.write opens, commits, or rolls back one transaction for this block.
        try dbQueue.write { db in
            try updates(db)
        }
    }

    func loadMigrationState() throws -> MigrationStateSnapshot {
        try dbQueue.read { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT imported_sources_json, parity_verified_sources_json, last_migration_at_seconds
                        FROM migration_state
                        WHERE id = 1
                        """
                )
            else {
                return MigrationStateSnapshot()
            }

            let imported = try Self.decodeImportedSources(
                from: row["imported_sources_json"] as String?
            )
            let parityVerified: [LegacyImportSource] =
                try Self.decodeJSON(
                    [LegacyImportSource].self,
                    from: row["parity_verified_sources_json"] as String?)
                ?? []
            let migrationTimestamp: Double? = row["last_migration_at_seconds"]

            return MigrationStateSnapshot(
                importedSources: imported,
                parityVerifiedSources: parityVerified,
                lastMigrationAt: migrationTimestamp.map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    func saveMigrationState(_ snapshot: MigrationStateSnapshot) throws {
        let report = try loadLegacyImportReport()
        try saveMigrationState(snapshot, report: report)
    }

    func loadLegacyImportReport() throws -> LegacyImportReport {
        try dbQueue.read { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT imported_sources_json FROM migration_state WHERE id = 1"
                ),
                let encoded = row["imported_sources_json"] as String?
            else {
                return LegacyImportReport(outcomes: [:], overallOutcome: .missing)
            }

            guard let envelope = try? Self.decodeJSON(LegacyImportStateEnvelope.self, from: encoded) else {
                return LegacyImportReport(outcomes: [:], overallOutcome: .missing)
            }

            return Self.makeLegacyImportReport(outcomes: envelope.outcomes)
        }
    }

    func importLegacyJSONIfNeeded() throws {
        var snapshot = try loadMigrationState()
        var importedSources = Set(snapshot.importedSources)
        var outcomes = try loadLegacyImportReport().outcomes

        for source in LegacyImportSource.allCases where !importedSources.contains(source) {
            let outcome: LegacyImportOutcome
            do {
                outcome = try importLegacySource(source)
            } catch is DecodingError {
                outcome = .malformed
                Self.logger.error(
                    "Legacy import malformed for \(source.rawValue, privacy: .public)"
                )
            }

            outcomes[source] = outcome
            if outcome != .missing {
                importedSources.insert(source)
            }

            snapshot = MigrationStateSnapshot(
                importedSources: LegacyImportSource.allCases.filter { importedSources.contains($0) },
                parityVerifiedSources: snapshot.parityVerifiedSources,
                lastMigrationAt: Date()
            )
            try saveMigrationState(
                snapshot,
                report: Self.makeLegacyImportReport(outcomes: outcomes)
            )
        }
    }

    private func importLegacySource(_ source: LegacyImportSource) throws -> LegacyImportOutcome {
        guard FileManager.default.fileExists(atPath: sourceURL(for: source).path) else {
            return .missing
        }

        switch source {
        case .dictationHistoryJSON:
            let entries = try Self.decodeJSONFile(
                [DictationHistoryEntry].self,
                at: paths.dictationHistoryJSONURL
            )
            guard try fetchHistoryEntries().isEmpty else { return .skippedNonempty }
            try replaceHistoryEntries(entries)
            return .imported(count: entries.count)

        case .voiceMemosJSON:
            let memos = try Self.decodeJSONFile([VoiceMemo].self, at: paths.voiceMemosJSONURL)
            guard try fetchMemos().isEmpty else { return .skippedNonempty }
            try replaceMemos(memos)
            return .imported(count: memos.count)

        case .vocabularyJSON:
            let terms = try Self.decodeJSONFile([VocabTerm].self, at: paths.vocabularyJSONURL)
            guard try fetchVocabularyTerms().isEmpty else { return .skippedNonempty }
            try replaceVocabularyTerms(terms)
            return .imported(count: terms.count)

        case .correctionsJSON:
            let legacyCorrections = try Self.decodeJSONFile(
                [LegacyCorrectionPayload].self,
                at: paths.correctionsJSONURL
            )
            guard try fetchCorrections().isEmpty else { return .skippedNonempty }
            try replaceCorrections(
                legacyCorrections.map {
                    CorrectionRecord(
                        originalText: $0.original,
                        correctedText: $0.corrected,
                        createdAt: $0.timestamp,
                        appliedCount: $0.appliedCount
                    )
                }
            )
            return .imported(count: legacyCorrections.count)
        }
    }

    private func sourceURL(for source: LegacyImportSource) -> URL {
        switch source {
        case .dictationHistoryJSON: return paths.dictationHistoryJSONURL
        case .voiceMemosJSON: return paths.voiceMemosJSONURL
        case .vocabularyJSON: return paths.vocabularyJSONURL
        case .correctionsJSON: return paths.correctionsJSONURL
        }
    }

    private func saveMigrationState(
        _ snapshot: MigrationStateSnapshot,
        report: LegacyImportReport
    ) throws {
        let envelope = LegacyImportStateEnvelope(
            importedSources: snapshot.importedSources,
            outcomes: report.outcomes
        )

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO migration_state (
                        id, imported_sources_json, parity_verified_sources_json, last_migration_at_seconds
                    ) VALUES (1, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        imported_sources_json = excluded.imported_sources_json,
                        parity_verified_sources_json = excluded.parity_verified_sources_json,
                        last_migration_at_seconds = excluded.last_migration_at_seconds
                    """,
                arguments: [
                    try Self.encodeJSONString(envelope),
                    try Self.encodeJSONString(snapshot.parityVerifiedSources),
                    snapshot.lastMigrationAt?.timeIntervalSince1970,
                ]
            )
        }
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_core_tables") { db in
            try db.create(table: "dictation_history") { table in
                table.column("id", .text).primaryKey()
                table.column("sort_order", .integer).notNull()
                table.column("text", .text).notNull()
                table.column("timestamp_seconds", .double).notNull()
                table.column("duration_seconds", .double).notNull()
                table.column("model", .text).notNull()
                table.column("output_method", .text).notNull()
            }

            try db.create(table: "voice_memos") { table in
                table.column("id", .text).primaryKey()
                table.column("sort_order", .integer).notNull()
                table.column("title", .text).notNull()
                table.column("created_at_seconds", .double).notNull()
                table.column("duration_seconds", .double).notNull()
                table.column("audio_file_name", .text).notNull()
                table.column("transcript", .text)
                table.column("transcript_words_json", .text)
                table.column("is_transcribing", .boolean).notNull()
                table.column("auto_transcribe", .boolean).notNull()
            }

            try db.create(table: "vocabulary_terms") { table in
                table.column("id", .text).primaryKey()
                table.column("sort_order", .integer).notNull()
                table.column("term", .text).notNull()
                table.column("category", .text).notNull()
                table.column("enabled", .boolean).notNull()
            }

            try db.create(table: "corrections") { table in
                table.column("id", .text).primaryKey()
                table.column("sort_order", .integer).notNull()
                table.column("original_text", .text).notNull()
                table.column("corrected_text", .text).notNull()
                table.column("created_at_seconds", .double).notNull()
                table.column("applied_count", .integer).notNull()
            }

            try db.create(table: "migration_state") { table in
                table.column("id", .integer).primaryKey(onConflict: .replace)
                table.column("imported_sources_json", .text)
                table.column("parity_verified_sources_json", .text)
                table.column("last_migration_at_seconds", .double)
            }
        }

        return migrator
    }

    private static func decodeImportedSources(from string: String?) throws -> [LegacyImportSource] {
        guard let string else { return [] }
        if let importedSources = try? decodeJSON([LegacyImportSource].self, from: string) {
            return importedSources
        }
        return try decodeJSON(LegacyImportStateEnvelope.self, from: string)?.importedSources ?? []
    }

    private static func makeLegacyImportReport(
        outcomes: [LegacyImportSource: LegacyImportOutcome]
    ) -> LegacyImportReport {
        guard !outcomes.isEmpty else {
            return LegacyImportReport(outcomes: outcomes, overallOutcome: .missing)
        }

        if outcomes.values.contains(where: {
            if case .malformed = $0 { return true }
            if case .partialFailure = $0 { return true }
            return false
        }) {
            return LegacyImportReport(outcomes: outcomes, overallOutcome: .partialFailure)
        }

        if outcomes.values.allSatisfy({ $0 == .missing }) {
            return LegacyImportReport(outcomes: outcomes, overallOutcome: .missing)
        }

        let importedCount = outcomes.values.reduce(into: 0) { count, outcome in
            if case let .imported(imported) = outcome {
                count += imported
            }
        }
        if outcomes.values.contains(where: {
            if case .imported = $0 { return true }
            return false
        }) {
            return LegacyImportReport(
                outcomes: outcomes,
                overallOutcome: .imported(count: importedCount)
            )
        }

        if outcomes.values.contains(.skippedNonempty) {
            return LegacyImportReport(outcomes: outcomes, overallOutcome: .skippedNonempty)
        }

        return LegacyImportReport(outcomes: outcomes, overallOutcome: .missing)
    }

    private static func makeHistoryEntry(from row: Row) throws -> DictationHistoryEntry {
        DictationHistoryEntry(
            id: try decodeUUID(from: row, table: "dictation_history"),
            text: row["text"],
            timestamp: Date(timeIntervalSince1970: row["timestamp_seconds"]),
            durationSeconds: row["duration_seconds"],
            model: row["model"],
            outputMethod: row["output_method"]
        )
    }

    private static func makeVoiceMemo(from row: Row) throws -> VoiceMemo {
        VoiceMemo(
            id: try decodeUUID(from: row, table: "voice_memos"),
            title: row["title"],
            createdAt: Date(timeIntervalSince1970: row["created_at_seconds"]),
            durationSeconds: row["duration_seconds"],
            audioFileName: row["audio_file_name"],
            transcript: row["transcript"],
            transcriptWords: try decodeTranscriptWords(from: row),
            isTranscribing: row["is_transcribing"],
            autoTranscribe: row["auto_transcribe"]
        )
    }

    private static func makeVocabTerm(from row: Row) throws -> VocabTerm {
        VocabTerm(
            id: try decodeUUID(from: row, table: "vocabulary_terms"),
            term: row["term"],
            category: row["category"],
            enabled: row["enabled"]
        )
    }

    private static func makeCorrectionRecord(from row: Row) throws -> CorrectionRecord {
        CorrectionRecord(
            id: try decodeUUID(from: row, table: "corrections"),
            originalText: row["original_text"],
            correctedText: row["corrected_text"],
            createdAt: Date(timeIntervalSince1970: row["created_at_seconds"]),
            appliedCount: row["applied_count"]
        )
    }

    private static func decodeUUID(from row: Row, table: String) throws -> UUID {
        let rawID: String? = row["id"]
        guard let rawID, let id = UUID(uuidString: rawID) else {
            throw SQLiteV2StoreError.rowDecodingCorruption(
                table: table,
                row: rawID ?? "<missing-id>",
                column: "id",
                reason: .invalidUUID
            )
        }
        return id
    }

    private static func decodeTranscriptWords(from row: Row) throws -> [TranscriptWord]? {
        do {
            return try decodeJSON(
                [TranscriptWord].self,
                from: row["transcript_words_json"] as String?
            )
        } catch {
            throw SQLiteV2StoreError.rowDecodingCorruption(
                table: "voice_memos",
                row: row["id"] as String? ?? "<missing-id>",
                column: "transcript_words_json",
                reason: .invalidSerializedData
            )
        }
    }

    private static func encodeJSONString<T: Encodable>(_ value: T?) throws -> String? {
        guard let value else { return nil }
        return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from string: String?) throws -> T?
    {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func decodeJSONFile<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }
}

/// Synchronous cache for store instances. Condition state is locked only while
/// reading/writing cache metadata; store initialization runs outside that lock.
private final class SQLiteV2StoreCache: @unchecked Sendable {
    private let condition = NSCondition()
    private var stores: [URL: SQLiteV2Store] = [:]
    private var constructing: Set<URL> = []

    func store(for url: URL, create: () -> SQLiteV2Store) -> SQLiteV2Store {
        condition.lock()
        while true {
            if let store = stores[url] {
                condition.unlock()
                return store
            }
            if constructing.insert(url).inserted {
                condition.unlock()
                break
            }
            condition.wait()
        }

        let created = create()

        condition.lock()
        if let existing = stores[url] {
            constructing.remove(url)
            condition.broadcast()
            condition.unlock()
            return existing
        }
        stores[url] = created
        constructing.remove(url)
        condition.broadcast()
        condition.unlock()
        return created
    }
}

private struct LegacyCorrectionPayload: Codable {
    let original: String
    let corrected: String
    let timestamp: Date
    let appliedCount: Int
}
