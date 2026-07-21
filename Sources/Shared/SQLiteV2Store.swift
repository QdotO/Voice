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

final class SQLiteV2Store {
    private static let logger = Logger(subsystem: "Whisper", category: "Persistence")
    private static let cacheLock = NSLock()
    private static var cache: [URL: SQLiteV2Store] = [:]

    static func shared(baseURL: URL = SharedStorage.baseDirectory()) -> SQLiteV2Store {
        let normalized = baseURL.resolvingSymlinksInPath().standardizedFileURL
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cache[normalized] {
            return cached
        }

        let store = SQLiteV2Store(baseURL: normalized)
        cache[normalized] = store
        return store
    }

    let paths: WhisperPersistencePaths
    private let dbQueue: DatabaseQueue

    private init(baseURL: URL) {
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

            dbQueue = try DatabaseQueue(path: paths.databaseURL.path)
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
            .map(Self.makeHistoryEntry(from:))
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
            .map(Self.makeVoiceMemo(from:))
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
            .map(Self.makeVocabTerm(from:))
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
            .map(Self.makeCorrectionRecord(from:))
        }
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

            let imported: [LegacyImportSource] =
                try Self.decodeJSON(
                    [LegacyImportSource].self,
                    from: row["imported_sources_json"] as String?)
                ?? []
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
                    try Self.encodeJSONString(snapshot.importedSources),
                    try Self.encodeJSONString(snapshot.parityVerifiedSources),
                    snapshot.lastMigrationAt?.timeIntervalSince1970,
                ]
            )
        }
    }

    private func importLegacyJSONIfNeeded() throws {
        var snapshot = try loadMigrationState()
        var importedSources = Set(snapshot.importedSources)
        var didImport = false

        didImport = try importLegacyFileIfNeeded(
            source: .dictationHistoryJSON,
            importedSources: &importedSources
        ) {
            let entries = try Self.decodeJSONFile(
                [DictationHistoryEntry].self,
                at: paths.dictationHistoryJSONURL
            ) ?? []
            if try fetchHistoryEntries().isEmpty {
                try replaceHistoryEntries(entries)
            }
        } || didImport

        didImport = try importLegacyFileIfNeeded(
            source: .voiceMemosJSON,
            importedSources: &importedSources
        ) {
            let memos = try Self.decodeJSONFile([VoiceMemo].self, at: paths.voiceMemosJSONURL) ?? []
            if try fetchMemos().isEmpty {
                try replaceMemos(memos)
            }
        } || didImport

        didImport = try importLegacyFileIfNeeded(
            source: .vocabularyJSON,
            importedSources: &importedSources
        ) {
            let terms = try Self.decodeJSONFile([VocabTerm].self, at: paths.vocabularyJSONURL) ?? []
            if try fetchVocabularyTerms().isEmpty {
                try replaceVocabularyTerms(terms)
            }
        } || didImport

        didImport = try importLegacyFileIfNeeded(
            source: .correctionsJSON,
            importedSources: &importedSources
        ) {
            let legacyCorrections =
                try Self.decodeJSONFile(
                    [LegacyCorrectionPayload].self,
                    at: paths.correctionsJSONURL
                ) ?? []
            if try fetchCorrections().isEmpty {
                try replaceCorrections(
                    legacyCorrections.map {
                        CorrectionRecord(
                            originalText: $0.original,
                            correctedText: $0.corrected,
                            createdAt: $0.timestamp,
                            appliedCount: $0.appliedCount
                        )
                    })
            }
        } || didImport

        guard importedSources != Set(snapshot.importedSources) || didImport else { return }

        snapshot = MigrationStateSnapshot(
            importedSources: LegacyImportSource.allCases.filter { importedSources.contains($0) },
            parityVerifiedSources: snapshot.parityVerifiedSources,
            lastMigrationAt: Date()
        )
        try saveMigrationState(snapshot)
    }

    private func importLegacyFileIfNeeded(
        source: LegacyImportSource,
        importedSources: inout Set<LegacyImportSource>,
        importBlock: () throws -> Void
    ) throws -> Bool {
        guard !importedSources.contains(source) else { return false }

        do {
            try importBlock()
            importedSources.insert(source)
            return true
        } catch {
            Self.logger.error("Legacy import failed for \(source.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
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

    private static func makeHistoryEntry(from row: Row) -> DictationHistoryEntry {
        DictationHistoryEntry(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            text: row["text"],
            timestamp: Date(timeIntervalSince1970: row["timestamp_seconds"]),
            durationSeconds: row["duration_seconds"],
            model: row["model"],
            outputMethod: row["output_method"]
        )
    }

    private static func makeVoiceMemo(from row: Row) -> VoiceMemo {
        VoiceMemo(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            title: row["title"],
            createdAt: Date(timeIntervalSince1970: row["created_at_seconds"]),
            durationSeconds: row["duration_seconds"],
            audioFileName: row["audio_file_name"],
            transcript: row["transcript"],
            transcriptWords: (try? decodeJSON(
                [TranscriptWord].self,
                from: row["transcript_words_json"] as String?
            )) ?? nil,
            isTranscribing: row["is_transcribing"],
            autoTranscribe: row["auto_transcribe"]
        )
    }

    private static func makeVocabTerm(from row: Row) -> VocabTerm {
        VocabTerm(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            term: row["term"],
            category: row["category"],
            enabled: row["enabled"]
        )
    }

    private static func makeCorrectionRecord(from row: Row) -> CorrectionRecord {
        CorrectionRecord(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            originalText: row["original_text"],
            correctedText: row["corrected_text"],
            createdAt: Date(timeIntervalSince1970: row["created_at_seconds"]),
            appliedCount: row["applied_count"]
        )
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

    private static func decodeJSONFile<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }
}

private struct LegacyCorrectionPayload: Codable {
    let original: String
    let corrected: String
    let timestamp: Date
    let appliedCount: Int
}
