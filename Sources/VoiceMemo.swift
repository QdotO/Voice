import Foundation

struct VoiceMemo: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var durationSeconds: Double
    let audioFileName: String
    var transcript: String?
    var transcriptWords: [TranscriptWord]?
    var isTranscribing: Bool
    var autoTranscribe: Bool

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        durationSeconds: Double,
        audioFileName: String,
        transcript: String? = nil,
        transcriptWords: [TranscriptWord]? = nil,
        isTranscribing: Bool = false,
        autoTranscribe: Bool = true
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.audioFileName = audioFileName
        self.transcript = transcript
        self.transcriptWords = transcriptWords
        self.isTranscribing = isTranscribing
        self.autoTranscribe = autoTranscribe
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case durationSeconds
        case audioFileName
        case transcript
        case transcriptWords
        case isTranscribing
        case autoTranscribe
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        audioFileName = try container.decode(String.self, forKey: .audioFileName)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        transcriptWords = try container.decodeIfPresent(
            [TranscriptWord].self, forKey: .transcriptWords)
        isTranscribing = try container.decodeIfPresent(Bool.self, forKey: .isTranscribing) ?? false
        autoTranscribe = try container.decodeIfPresent(Bool.self, forKey: .autoTranscribe) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(audioFileName, forKey: .audioFileName)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(transcriptWords, forKey: .transcriptWords)
        try container.encode(isTranscribing, forKey: .isTranscribing)
        try container.encode(autoTranscribe, forKey: .autoTranscribe)
    }
}

struct TranscriptWord: Codable, Hashable {
    let word: String
    let start: Double
    let end: Double
}
