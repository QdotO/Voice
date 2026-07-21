import XCTest

@testable import WhisperShared

final class DefaultTextInsertionServiceTests: XCTestCase {
    func testAXInsertStopsFallbackChainOnSuccess() async throws {
        let recorder = InsertionRecorder(axResult: true)
        let service = DefaultTextInsertionService(executor: await recorder.executor)
        let request = TextInsertionRequest(
            text: "hello",
            targetApp: InsertionAppProfile(
                bundleIdentifier: "com.microsoft.VSCode",
                applicationName: "VS Code",
                preferredStrategy: .axInsert,
                fallbackStrategies: [.paste, .type]
            )
        )

        let result = try await service.insert(request)

        XCTAssertEqual(result, TextInsertionResult(strategy: .axInsert, usedClipboard: false))
        let attempts = await recorder.attempts()
        XCTAssertEqual(attempts, ["ax"])
    }

    func testAXInsertFallsBackToPaste() async throws {
        let recorder = InsertionRecorder(axResult: false)
        let service = DefaultTextInsertionService(executor: await recorder.executor)
        let request = TextInsertionRequest(
            text: "hello",
            targetApp: InsertionAppProfile(
                bundleIdentifier: "com.microsoft.VSCode",
                applicationName: "VS Code",
                preferredStrategy: .axInsert,
                fallbackStrategies: [.paste, .type]
            ),
            preserveClipboard: true
        )

        let result = try await service.insert(request)

        XCTAssertEqual(result, TextInsertionResult(strategy: .paste, usedClipboard: true))
        let attempts = await recorder.attempts()
        XCTAssertEqual(attempts, ["ax", "paste:true"])
    }

    func testLongTextSkipsTypingFallback() async {
        let recorder = InsertionRecorder(
            pasteError: StubFailure(),
            typeError: StubFailure()
        )
        let service = DefaultTextInsertionService(
            executor: await recorder.executor,
            maximumTypingLength: 10
        )
        let request = TextInsertionRequest(
            text: "this should be pasted because it is too long",
            targetApp: InsertionAppProfile(
                bundleIdentifier: "com.apple.Terminal",
                applicationName: "Terminal",
                preferredStrategy: .type,
                fallbackStrategies: [.paste]
            )
        )

        do {
            _ = try await service.insert(request)
            XCTFail("Expected insertion to fail")
        } catch let error as TextInsertionServiceError {
            XCTAssertEqual(
                error,
                .allStrategiesFailed(attempted: [.paste], lastFailure: StubFailure().localizedDescription)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let attempts = await recorder.attempts()
        XCTAssertEqual(attempts, ["paste:true"])
    }

    func testShortSingleLineTextAllowsTypingFallback() async throws {
        let recorder = InsertionRecorder(pasteError: StubFailure())
        let service = DefaultTextInsertionService(
            executor: await recorder.executor,
            maximumTypingLength: 20
        )
        let request = TextInsertionRequest(
            text: "short",
            targetApp: InsertionAppProfile(
                bundleIdentifier: nil,
                applicationName: "Unknown App",
                preferredStrategy: .paste,
                fallbackStrategies: [.type]
            )
        )

        let result = try await service.insert(request)

        XCTAssertEqual(result, TextInsertionResult(strategy: .type, usedClipboard: false))
        let attempts = await recorder.attempts()
        XCTAssertEqual(attempts, ["paste:true", "type"])
    }
}

private struct StubFailure: LocalizedError, Equatable {
    var errorDescription: String? {
        "stub failure"
    }
}

private actor InsertionRecorder {
    private let axResult: Bool
    private let axError: Error?
    private let pasteError: Error?
    private let typeError: Error?
    private var recordedAttempts: [String] = []

    init(
        axResult: Bool = false,
        axError: Error? = nil,
        pasteError: Error? = nil,
        typeError: Error? = nil
    ) {
        self.axResult = axResult
        self.axError = axError
        self.pasteError = pasteError
        self.typeError = typeError
    }

    var executor: TextInsertionExecutor {
        TextInsertionExecutor(
            insertUsingAX: { text in
                _ = text
                await self.record("ax")
                if let axError = self.axError {
                    throw axError
                }
                return self.axResult
            },
            paste: { _, preserveClipboard in
                await self.record("paste:\(preserveClipboard)")
                if let pasteError = self.pasteError {
                    throw pasteError
                }
            },
            type: { _ in
                await self.record("type")
                if let typeError = self.typeError {
                    throw typeError
                }
            }
        )
    }

    func record(_ attempt: String) {
        recordedAttempts.append(attempt)
    }

    func attempts() -> [String] {
        recordedAttempts
    }
}
