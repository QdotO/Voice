import Foundation

public typealias DictationUpdateStream = AsyncThrowingStream<DictationSessionUpdate, Error>

public protocol WhisperEngine: Sendable {
    func prepare(_ request: WhisperEnginePreparation) async throws
    func startDictation(_ request: DictationSessionRequest) async throws -> DictationUpdateStream
    func stopDictation(sessionID: UUID) async
    func transcribeMemo(_ request: MemoTranscriptionRequest) async throws -> MemoTranscriptionResult
}

public struct WhisperEnginePreparation: Equatable, Sendable {
    public let profile: ModelProfile
    public let rawModelOverride: String?

    public init(profile: ModelProfile, rawModelOverride: String? = nil) {
        self.profile = profile
        self.rawModelOverride = Self.normalize(rawModelOverride)
    }

    public var resolvedModelName: String {
        profile.resolvedModelName(rawOverride: rawModelOverride)
    }

    private static func normalize(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }
}

public struct DictationSessionRequest: Equatable, Sendable {
    public let sessionID: UUID
    public let profile: ModelProfile
    public let localeIdentifier: String
    public let prompt: String

    public init(
        sessionID: UUID = UUID(),
        profile: ModelProfile,
        localeIdentifier: String = "en_US",
        prompt: String = ""
    ) {
        self.sessionID = sessionID
        self.profile = profile
        self.localeIdentifier = localeIdentifier
        self.prompt = prompt
    }
}

public enum DictationSessionState: String, CaseIterable, Codable, Sendable {
    case idle
    case preparing
    case recording
    case partial
    case finalizing
    case completed
    case failed

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            return true
        default:
            return false
        }
    }
}

public struct DictationSessionUpdate: Equatable, Sendable {
    public let sessionID: UUID
    public let state: DictationSessionState
    public let transcript: String
    public let words: [TranscriptWord]
    public let errorDescription: String?

    public init(
        sessionID: UUID,
        state: DictationSessionState,
        transcript: String = "",
        words: [TranscriptWord] = [],
        errorDescription: String? = nil
    ) {
        self.sessionID = sessionID
        self.state = state
        self.transcript = transcript
        self.words = words
        self.errorDescription = errorDescription
    }
}

public protocol DictationCoordinator: Sendable {
    func startDictation() async throws -> DictationUpdateStream
    func stopDictation() async
}

public struct MemoTranscriptionRequest: Equatable, Sendable {
    public let memoID: UUID
    public let audioFileURL: URL
    public let profile: ModelProfile
    public let localeIdentifier: String
    public let prompt: String

    public init(
        memoID: UUID = UUID(),
        audioFileURL: URL,
        profile: ModelProfile,
        localeIdentifier: String = "en_US",
        prompt: String = ""
    ) {
        self.memoID = memoID
        self.audioFileURL = audioFileURL
        self.profile = profile
        self.localeIdentifier = localeIdentifier
        self.prompt = prompt
    }
}

public struct MemoTranscriptionResult: Equatable, Sendable {
    public let memoID: UUID
    public let payload: TranscriptionPayload
    public let durationSeconds: Double

    public init(memoID: UUID, payload: TranscriptionPayload, durationSeconds: Double) {
        self.memoID = memoID
        self.payload = payload
        self.durationSeconds = durationSeconds
    }
}

public protocol MemoCoordinator: Sendable {
    func startRecording() async throws -> UUID
    func stopRecording() async throws -> VoiceMemo
    func transcribeMemo(id: UUID) async throws -> MemoTranscriptionResult
}

public enum TextInsertionStrategy: String, CaseIterable, Codable, Sendable {
    case axInsert
    case paste
    case type
}

public struct InsertionAppProfile: Equatable, Codable, Sendable {
    public let bundleIdentifier: String?
    public let applicationName: String
    public let version: String?
    public let preferredStrategy: TextInsertionStrategy
    public let fallbackStrategies: [TextInsertionStrategy]

    public init(
        bundleIdentifier: String?,
        applicationName: String,
        version: String? = nil,
        preferredStrategy: TextInsertionStrategy,
        fallbackStrategies: [TextInsertionStrategy] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.version = version
        self.preferredStrategy = preferredStrategy
        self.fallbackStrategies = fallbackStrategies
    }
}

public struct TextInsertionRequest: Equatable, Sendable {
    public let text: String
    public let targetApp: InsertionAppProfile?
    public let preserveClipboard: Bool

    public init(
        text: String,
        targetApp: InsertionAppProfile? = nil,
        preserveClipboard: Bool = true
    ) {
        self.text = text
        self.targetApp = targetApp
        self.preserveClipboard = preserveClipboard
    }
}

public struct TextInsertionResult: Equatable, Sendable {
    public let strategy: TextInsertionStrategy
    public let usedClipboard: Bool

    public init(strategy: TextInsertionStrategy, usedClipboard: Bool) {
        self.strategy = strategy
        self.usedClipboard = usedClipboard
    }
}

public protocol TextInsertionService: Sendable {
    func insert(_ request: TextInsertionRequest) async throws -> TextInsertionResult
}

public struct CorrectionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let originalText: String
    public let correctedText: String
    public let createdAt: Date
    public let appliedCount: Int

    public init(
        id: UUID = UUID(),
        originalText: String,
        correctedText: String,
        createdAt: Date = Date(),
        appliedCount: Int = 0
    ) {
        self.id = id
        self.originalText = originalText
        self.correctedText = correctedText
        self.createdAt = createdAt
        self.appliedCount = appliedCount
    }
}

public enum LegacyImportSource: String, CaseIterable, Codable, Sendable {
    case dictationHistoryJSON
    case voiceMemosJSON
    case vocabularyJSON
    case correctionsJSON
}

public struct MigrationStateSnapshot: Equatable, Sendable {
    public let importedSources: [LegacyImportSource]
    public let parityVerifiedSources: [LegacyImportSource]
    public let lastMigrationAt: Date?

    public init(
        importedSources: [LegacyImportSource] = [],
        parityVerifiedSources: [LegacyImportSource] = [],
        lastMigrationAt: Date? = nil
    ) {
        self.importedSources = importedSources
        self.parityVerifiedSources = parityVerifiedSources
        self.lastMigrationAt = lastMigrationAt
    }
}

public protocol HistoryRepository: Sendable {
    func fetchAllHistory() async throws -> [DictationHistoryEntry]
    func saveHistoryEntry(_ entry: DictationHistoryEntry) async throws
    func deleteHistoryEntry(id: UUID) async throws
    func clearHistory() async throws
}

public protocol MemoRepository: Sendable {
    func fetchAllMemos() async throws -> [VoiceMemo]
    func saveMemo(_ memo: VoiceMemo) async throws
    func deleteMemo(id: UUID) async throws
}

public protocol VocabularyRepository: Sendable {
    func fetchAllTerms() async throws -> [VocabTerm]
    func saveTerm(_ term: VocabTerm) async throws
    func deleteTerm(id: UUID) async throws
}

public protocol CorrectionRepository: Sendable {
    func fetchAllCorrections() async throws -> [CorrectionRecord]
    func saveCorrection(_ correction: CorrectionRecord) async throws
    func deleteCorrection(id: UUID) async throws
}

public protocol MigrationRepository: Sendable {
    func loadMigrationState() async throws -> MigrationStateSnapshot
    func saveMigrationState(_ snapshot: MigrationStateSnapshot) async throws
}
