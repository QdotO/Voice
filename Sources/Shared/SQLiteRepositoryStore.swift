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
        self.store = SQLiteV2Store.shared(baseURL: baseURL)
    }

    public func fetchAllHistory() async throws -> [DictationHistoryEntry] {
        try store.fetchHistoryEntries().sorted { $0.timestamp > $1.timestamp }
    }

    public func saveHistoryEntry(_ entry: DictationHistoryEntry) async throws {
        var entries = try store.fetchHistoryEntries()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try store.replaceHistoryEntries(entries)
    }

    public func deleteHistoryEntry(id: UUID) async throws {
        var entries = try store.fetchHistoryEntries()
        entries.removeAll { $0.id == id }
        try store.replaceHistoryEntries(entries)
    }

    public func clearHistory() async throws {
        try store.replaceHistoryEntries([])
    }

    public func fetchAllMemos() async throws -> [VoiceMemo] {
        try store.fetchMemos().sorted { $0.createdAt > $1.createdAt }
    }

    public func saveMemo(_ memo: VoiceMemo) async throws {
        var memos = try store.fetchMemos()
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            memos[index] = memo
        } else {
            memos.append(memo)
        }
        try store.replaceMemos(memos)
    }

    public func deleteMemo(id: UUID) async throws {
        var memos = try store.fetchMemos()
        memos.removeAll { $0.id == id }
        try store.replaceMemos(memos)
    }

    public func fetchAllTerms() async throws -> [VocabTerm] {
        try store.fetchVocabularyTerms()
    }

    public func saveTerm(_ term: VocabTerm) async throws {
        var terms = try store.fetchVocabularyTerms()
        if let index = terms.firstIndex(where: { $0.id == term.id }) {
            terms[index] = term
        } else {
            terms.append(term)
        }
        try store.replaceVocabularyTerms(terms)
    }

    public func deleteTerm(id: UUID) async throws {
        var terms = try store.fetchVocabularyTerms()
        terms.removeAll { $0.id == id }
        try store.replaceVocabularyTerms(terms)
    }

    public func fetchAllCorrections() async throws -> [CorrectionRecord] {
        try store.fetchCorrections()
    }

    public func saveCorrection(_ correction: CorrectionRecord) async throws {
        var corrections = try store.fetchCorrections()
        if let index = corrections.firstIndex(where: { $0.id == correction.id }) {
            corrections[index] = correction
        } else {
            corrections.append(correction)
        }
        try store.replaceCorrections(corrections)
    }

    public func deleteCorrection(id: UUID) async throws {
        var corrections = try store.fetchCorrections()
        corrections.removeAll { $0.id == id }
        try store.replaceCorrections(corrections)
    }

    public func loadMigrationState() async throws -> MigrationStateSnapshot {
        try store.loadMigrationState()
    }

    public func saveMigrationState(_ snapshot: MigrationStateSnapshot) async throws {
        try store.saveMigrationState(snapshot)
    }
}
