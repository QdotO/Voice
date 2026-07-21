import WhisperShared

enum SystemTextInsertionService {
    static func make() -> DefaultTextInsertionService {
        DefaultTextInsertionService(
            executor: TextInsertionExecutor(
                insertUsingAX: { text in
                    try await Task { @MainActor in
                        try TextInjector().insertIntoFocusedElementAdvanced(text)
                    }.value
                },
                paste: { text, preserveClipboard in
                    try await Task { @MainActor in
                        try await TextInjector().pasteText(text, preserveClipboard: preserveClipboard)
                    }.value
                },
                type: { text in
                    try await Task { @MainActor in
                        try await TextInjector().typeText(text)
                    }.value
                }
            )
        )
    }
}
