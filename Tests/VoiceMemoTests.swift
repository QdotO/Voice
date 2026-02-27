import XCTest

@testable import WhisperShared

final class VoiceMemoTests: XCTestCase {
    // MARK: - Initialization

    func testInitGeneratesUUID() {
        let memo1 = VoiceMemo(title: "A", durationSeconds: 1.0, audioFileName: "a.m4a")
        let memo2 = VoiceMemo(title: "B", durationSeconds: 1.0, audioFileName: "b.m4a")
        XCTAssertNotEqual(memo1.id, memo2.id)
    }

    func testInitCapturesTimestamp() {
        let before = Date()
        let memo = VoiceMemo(title: "Test", durationSeconds: 1.0, audioFileName: "test.m4a")
        let after = Date()
        XCTAssertGreaterThanOrEqual(memo.createdAt, before)
        XCTAssertLessThanOrEqual(memo.createdAt, after)
    }

    func testInitDefaultIsTranscribingFalse() {
        let memo = VoiceMemo(title: "Test", durationSeconds: 1.0, audioFileName: "test.m4a")
        XCTAssertFalse(memo.isTranscribing)
    }

    func testInitDefaultAutoTranscribeTrue() {
        let memo = VoiceMemo(title: "Test", durationSeconds: 1.0, audioFileName: "test.m4a")
        XCTAssertTrue(memo.autoTranscribe)
    }

    func testInitTranscriptDefaultNil() {
        let memo = VoiceMemo(title: "Test", durationSeconds: 1.0, audioFileName: "test.m4a")
        XCTAssertNil(memo.transcript)
    }

    func testInitTranscriptWordsDefaultNil() {
        let memo = VoiceMemo(title: "Test", durationSeconds: 1.0, audioFileName: "test.m4a")
        XCTAssertNil(memo.transcriptWords)
    }

    func testInitWithAllParameters() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1000)
        let words = [TranscriptWord(word: "hello", start: 0.0, end: 0.5)]
        let memo = VoiceMemo(
            id: id,
            title: "Full",
            createdAt: date,
            durationSeconds: 60.0,
            audioFileName: "full.m4a",
            transcript: "hello world",
            transcriptWords: words,
            isTranscribing: true,
            autoTranscribe: false
        )
        XCTAssertEqual(memo.id, id)
        XCTAssertEqual(memo.title, "Full")
        XCTAssertEqual(memo.createdAt, date)
        XCTAssertEqual(memo.durationSeconds, 60.0)
        XCTAssertEqual(memo.audioFileName, "full.m4a")
        XCTAssertEqual(memo.transcript, "hello world")
        XCTAssertEqual(memo.transcriptWords, words)
        XCTAssertTrue(memo.isTranscribing)
        XCTAssertFalse(memo.autoTranscribe)
    }

    // MARK: - Codable Roundtrip

    func testCodableRoundtripPreservesValues() throws {
        let words = [
            TranscriptWord(word: "hello", start: 0.0, end: 0.5),
            TranscriptWord(word: "world", start: 0.6, end: 1.0),
        ]
        let original = VoiceMemo(
            title: "Roundtrip",
            durationSeconds: 42.5,
            audioFileName: "roundtrip.m4a",
            transcript: "hello world",
            transcriptWords: words,
            isTranscribing: true,
            autoTranscribe: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoiceMemo.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.durationSeconds, original.durationSeconds)
        XCTAssertEqual(decoded.audioFileName, original.audioFileName)
        XCTAssertEqual(decoded.transcript, original.transcript)
        XCTAssertEqual(decoded.transcriptWords, original.transcriptWords)
        XCTAssertEqual(decoded.isTranscribing, original.isTranscribing)
        XCTAssertEqual(decoded.autoTranscribe, original.autoTranscribe)
    }

    func testDecodeMissingIsTranscribingDefaultsFalse() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "title": "Old",
            "createdAt": Date().timeIntervalSinceReferenceDate,
            "durationSeconds": 10.0,
            "audioFileName": "old.m4a",
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(VoiceMemo.self, from: data)
        XCTAssertFalse(decoded.isTranscribing)
    }

    func testDecodeMissingAutoTranscribeDefaultsTrue() throws {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "title": "Old",
            "createdAt": Date().timeIntervalSinceReferenceDate,
            "durationSeconds": 10.0,
            "audioFileName": "old.m4a",
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(VoiceMemo.self, from: data)
        XCTAssertTrue(decoded.autoTranscribe)
    }

    func testDecodeWithNilTranscript() throws {
        let memo = VoiceMemo(title: "NoTranscript", durationSeconds: 5.0, audioFileName: "no.m4a")
        let data = try JSONEncoder().encode(memo)
        let decoded = try JSONDecoder().decode(VoiceMemo.self, from: data)
        XCTAssertNil(decoded.transcript)
    }

    // MARK: - Equatable

    func testEquatable() {
        let id = UUID()
        let date = Date()
        let memo1 = VoiceMemo(
            id: id, title: "T", createdAt: date, durationSeconds: 1.0, audioFileName: "a.m4a")
        let memo2 = VoiceMemo(
            id: id, title: "T", createdAt: date, durationSeconds: 1.0, audioFileName: "a.m4a")
        XCTAssertEqual(memo1, memo2)
    }

    // MARK: - TranscriptWord

    func testTranscriptWordInit() {
        let word = TranscriptWord(word: "hello", start: 1.5, end: 2.0)
        XCTAssertEqual(word.word, "hello")
        XCTAssertEqual(word.start, 1.5)
        XCTAssertEqual(word.end, 2.0)
    }

    func testTranscriptWordHashable() {
        let word1 = TranscriptWord(word: "hello", start: 0.0, end: 0.5)
        let word2 = TranscriptWord(word: "hello", start: 0.0, end: 0.5)
        XCTAssertEqual(word1, word2)

        var set = Set<TranscriptWord>()
        set.insert(word1)
        set.insert(word2)
        XCTAssertEqual(set.count, 1)
    }
}
