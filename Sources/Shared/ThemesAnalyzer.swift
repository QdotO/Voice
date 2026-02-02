import Foundation

public struct ThemesAnalysis: Equatable {
    public let title: String
    public let bullets: [String]
    public let confidence: Double
    public let source: String

    public static let placeholder = ThemesAnalysis(
        title: "No analysis yet",
        bullets: ["Connect analysis to see themes."],
        confidence: 0,
        source: "placeholder"
    )
}

public protocol ThemesAnalyzing {
    func analyze(texts: [String]) async throws -> ThemesAnalysis
}

public final class CopilotBridgeClient: ThemesAnalyzing {
    private let endpoint: URL

    public init?(endpoint: String) {
        guard let url = URL(string: endpoint) else { return nil }
        self.endpoint = url
    }

    public func analyze(texts: [String]) async throws -> ThemesAnalysis {
        let requestBody = CopilotBridgeRequest(texts: texts)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(CopilotBridgeResponse.self, from: data)
        var bullets = decoded.themes
        var source = "copilot-bridge"

        if let error = decoded.error, !error.isEmpty {
            bullets.append("Copilot error: \(error)")
            source = "copilot-error"
        }

        return ThemesAnalysis(
            title: decoded.summary,
            bullets: bullets,
            confidence: decoded.confidence,
            source: source
        )
    }
}

struct CopilotBridgeRequest: Codable {
    let texts: [String]
}

struct CopilotBridgeResponse: Codable {
    let summary: String
    let themes: [String]
    let confidence: Double
    let error: String?
}

public struct KeywordThemesAnalyzer: ThemesAnalyzing {
    private let stopwords: Set<String> = [
        "the", "and", "that", "this", "with", "from", "they", "their", "there",
        "about", "would", "could", "should", "what", "when", "where", "which",
        "your", "have", "has", "had", "into", "just", "like", "been", "were",
        "will", "then", "than", "them", "some", "more", "less", "very", "much",
        "over", "under", "also", "only", "using", "used", "use", "my", "our",
        "you", "are", "for", "not", "but", "can", "did", "does", "its", "was",
    ]

    public func analyze(texts: [String]) async throws -> ThemesAnalysis {
        let combined = texts.joined(separator: " ")
        let tokens =
            combined
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopwords.contains($0) }

        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
        }

        let top =
            counts
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { $0.key }

        let bullets =
            top.isEmpty
            ? ["Not enough recent content to detect themes."]
            : ["Frequent topics: \(top.joined(separator: ", "))"]

        return ThemesAnalysis(
            title: "Local theme scan",
            bullets: bullets,
            confidence: 0.32,
            source: "keyword-fallback"
        )
    }
}

public struct ThemesAnalyzer {
    public static func analyze(
        texts: [String],
        useCopilot: Bool,
        copilotEndpoint: String
    ) async -> ThemesAnalysis {
        let cleaned =
            texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else { return .placeholder }

        if useCopilot, let client = CopilotBridgeClient(endpoint: copilotEndpoint) {
            do {
                return try await client.analyze(texts: cleaned)
            } catch {
                // Fall back to local keyword analysis
                return (try? await KeywordThemesAnalyzer().analyze(texts: cleaned))
                    ?? .placeholder
            }
        }

        return (try? await KeywordThemesAnalyzer().analyze(texts: cleaned))
            ?? .placeholder
    }
}
