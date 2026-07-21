import Foundation

public struct TextInsertionExecutor: Sendable {
    public typealias AXInsert = @Sendable (String) async throws -> Bool
    public typealias Paste = @Sendable (String, Bool) async throws -> Void
    public typealias Typing = @Sendable (String) async throws -> Void

    public let insertUsingAX: AXInsert
    public let paste: Paste
    public let type: Typing

    public init(
        insertUsingAX: @escaping AXInsert,
        paste: @escaping Paste,
        type: @escaping Typing
    ) {
        self.insertUsingAX = insertUsingAX
        self.paste = paste
        self.type = type
    }
}

public enum TextInsertionServiceError: LocalizedError, Equatable, Sendable {
    case noEligibleStrategies(textLength: Int, multiline: Bool)
    case allStrategiesFailed(attempted: [TextInsertionStrategy], lastFailure: String?)

    public var errorDescription: String? {
        switch self {
        case let .noEligibleStrategies(textLength, multiline):
            return "No eligible insertion strategy for text length \(textLength) and multiline=\(multiline)."
        case let .allStrategiesFailed(attempted, lastFailure):
            let attemptedLabel = attempted.map(\.rawValue).joined(separator: ", ")
            if let lastFailure, !lastFailure.isEmpty {
                return "All insertion strategies failed (\(attemptedLabel)): \(lastFailure)"
            }
            return "All insertion strategies failed (\(attemptedLabel))."
        }
    }
}

public actor DefaultTextInsertionService: TextInsertionService {
    private let executor: TextInsertionExecutor
    private let maximumTypingLength: Int

    public init(
        executor: TextInsertionExecutor,
        maximumTypingLength: Int = 80
    ) {
        self.executor = executor
        self.maximumTypingLength = maximumTypingLength
    }

    public func insert(_ request: TextInsertionRequest) async throws -> TextInsertionResult {
        let strategies = orderedStrategies(for: request)
        var attempted: [TextInsertionStrategy] = []
        var lastFailure: String?

        for strategy in strategies {
            guard canAttempt(strategy, for: request.text) else { continue }
            attempted.append(strategy)

            do {
                switch strategy {
                case .axInsert:
                    if try await executor.insertUsingAX(request.text) {
                        return TextInsertionResult(strategy: .axInsert, usedClipboard: false)
                    }
                    lastFailure = "AX insertion returned false."
                case .paste:
                    try await executor.paste(request.text, request.preserveClipboard)
                    return TextInsertionResult(strategy: .paste, usedClipboard: true)
                case .type:
                    try await executor.type(request.text)
                    return TextInsertionResult(strategy: .type, usedClipboard: false)
                }
            } catch {
                lastFailure = error.localizedDescription
            }
        }

        if attempted.isEmpty {
            throw TextInsertionServiceError.noEligibleStrategies(
                textLength: request.text.count,
                multiline: request.text.contains(where: \.isNewline)
            )
        }

        throw TextInsertionServiceError.allStrategiesFailed(
            attempted: attempted,
            lastFailure: lastFailure
        )
    }

    private func orderedStrategies(for request: TextInsertionRequest) -> [TextInsertionStrategy] {
        if let targetApp = request.targetApp {
            return uniqueStrategies([targetApp.preferredStrategy] + targetApp.fallbackStrategies)
        }
        return [.type, .paste]
    }

    private func canAttempt(_ strategy: TextInsertionStrategy, for text: String) -> Bool {
        switch strategy {
        case .type:
            return text.count <= maximumTypingLength && !text.contains(where: \.isNewline)
        case .axInsert, .paste:
            return !text.isEmpty
        }
    }

    private func uniqueStrategies(_ values: [TextInsertionStrategy]) -> [TextInsertionStrategy] {
        var seen: Set<TextInsertionStrategy> = []
        return values.filter { seen.insert($0).inserted }
    }
}
