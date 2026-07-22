import Foundation

public actor SQLiteRepositoryStore:
    HistoryRepository,
    MemoRepository,
    VocabularyRepository,
    CorrectionRepository,
    MigrationRepository
{
    private let store: SQLiteV2Store

    public init(baseURL: URL = SharedStorage.baseDirectory()) {
        self.store = SQLiteV2Store(baseURL: baseURL)
    }

    public func fetchAllHistory() async throws -> [DictationHistoryEntry] {
        try store.fetchHistoryEntries().sorted { $0.timestamp > $1.timestamp }
    }

    public func saveHistoryEntry(_ entry: DictationHistoryEntry) async throws {
        try store.upsertHistoryEntry(entry)
    }

    public func saveHistoryEntries(_ entries: [DictationHistoryEntry]) async throws {
        try store.upsertHistoryEntries(entries)
    }

    public func deleteHistoryEntry(id: UUID) async throws {
        try store.deleteHistoryEntry(id: id)
    }

    public func deleteHistoryEntries(ids: [UUID]) async throws {
        try store.deleteHistoryEntries(ids: ids)
    }

    public func clearHistory() async throws {
        try store.deleteAllHistory()
    }

    public func fetchAllMemos() async throws -> [VoiceMemo] {
        try store.fetchMemos().sorted { $0.createdAt > $1.createdAt }
    }

    public func saveMemo(_ memo: VoiceMemo) async throws {
        try store.upsertMemo(memo)
    }

    public func saveMemos(_ memos: [VoiceMemo]) async throws {
        try store.upsertMemos(memos)
    }

    public func deleteMemo(id: UUID) async throws {
        try store.deleteMemo(id: id)
    }

    public func deleteMemos(ids: [UUID]) async throws {
        try store.deleteMemos(ids: ids)
    }

    public func fetchAllTerms() async throws -> [VocabTerm] {
        try store.fetchVocabularyTerms()
    }

    public func saveTerm(_ term: VocabTerm) async throws {
        try store.upsertVocabularyTerm(term)
    }

    public func saveTerms(_ terms: [VocabTerm]) async throws {
        try store.upsertVocabularyTerms(terms)
    }

    public func deleteTerm(id: UUID) async throws {
        try store.deleteVocabularyTerm(id: id)
    }

    public func deleteTerms(ids: [UUID]) async throws {
        try store.deleteVocabularyTerms(ids: ids)
    }

    public func fetchAllCorrections() async throws -> [CorrectionRecord] {
        try store.fetchCorrections()
    }

    public func saveCorrection(_ correction: CorrectionRecord) async throws {
        try store.upsertCorrection(correction)
    }

    public func saveCorrections(_ corrections: [CorrectionRecord]) async throws {
        try store.upsertCorrections(corrections)
    }

    public func deleteCorrection(id: UUID) async throws {
        try store.deleteCorrection(id: id)
    }

    public func deleteCorrections(ids: [UUID]) async throws {
        try store.deleteCorrections(ids: ids)
    }

    public func loadMigrationState() async throws -> MigrationStateSnapshot {
        try store.loadMigrationState()
    }

    public func saveMigrationState(_ snapshot: MigrationStateSnapshot) async throws {
        try store.saveMigrationState(snapshot)
    }
}
