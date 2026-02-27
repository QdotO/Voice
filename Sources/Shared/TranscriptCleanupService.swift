import Foundation

public struct TranscriptCleanupResult: Equatable {
    public let cleanedText: String
    public let source: String
    public let error: String?

    public init(cleanedText: String, source: String, error: String? = nil) {
        self.cleanedText = cleanedText
        self.source = source
        self.error = error
    }
}

public struct TranscriptCleanupService {
    public static func suggestCleanup(
        text: String,
        useCopilot: Bool,
        copilotAnalyzeEndpoint: String
    ) async -> TranscriptCleanupResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TranscriptCleanupResult(cleanedText: "", source: "empty")
        }

        if useCopilot, let url = cleanupEndpoint(fromAnalyzeEndpoint: copilotAnalyzeEndpoint) {
            do {
                let cleaned = try await requestCleanup(text: trimmed, endpoint: url)
                let normalized = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    return TranscriptCleanupResult(cleanedText: cleaned, source: "copilot-bridge")
                }
            } catch {
                let fallback = basicCleanup(trimmed)
                return TranscriptCleanupResult(
                    cleanedText: fallback,
                    source: "local-fallback",
                    error: error.localizedDescription
                )
            }
        }

        return TranscriptCleanupResult(cleanedText: basicCleanup(trimmed), source: "local")
    }

    private static func cleanupEndpoint(fromAnalyzeEndpoint endpoint: String) -> URL? {
        guard var components = URLComponents(string: endpoint) else { return nil }

        if components.path.hasSuffix("/analyze") {
            let base = components.path.dropLast("/analyze".count)
            components.path = "\(base)/cleanup"
        } else if components.path.isEmpty || components.path == "/" {
            components.path = "/cleanup"
        } else if !components.path.hasSuffix("/cleanup") {
            components.path += components.path.hasSuffix("/") ? "cleanup" : "/cleanup"
        }

        return components.url
    }

    private struct CleanupRequest: Codable {
        let text: String
    }

    private struct CleanupResponse: Codable {
        let cleanedText: String
        let error: String?
    }

    private static func requestCleanup(text: String, endpoint: URL) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CleanupRequest(text: text))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(CleanupResponse.self, from: data)
        if let error = decoded.error, !error.isEmpty {
            throw NSError(domain: "TranscriptCleanupService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: error
            ])
        }
        return decoded.cleanedText
    }

    private static func basicCleanup(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(of: "\r\n", with: "\n")
        value = value.replacingOccurrences(of: "\r", with: "\n")

        while value.contains("\n\n\n") {
            value = value.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        value = value.replacingOccurrences(of: "\t", with: " ")
        while value.contains("  ") {
            value = value.replacingOccurrences(of: "  ", with: " ")
        }

        value = value.replacingOccurrences(of: " ,", with: ",")
        value = value.replacingOccurrences(of: " .", with: ".")
        value = value.replacingOccurrences(of: " !", with: "!")
        value = value.replacingOccurrences(of: " ?", with: "?")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

